import SwiftUI
import CoreLocation

struct SolarOffsetArcSlider: View {
    @Binding var offsetMinutes: Double
    let eventType: SolarEvent
    let device: WLEDDevice
    var disableClipping: Bool = false
    var useExternalGradient: Bool = false
    
    private let range: ClosedRange<Double> = -120...120
    
    @State private var sunriseTime: Date?
    @State private var sunsetTime: Date?
    @State private var nextEventTime: Date?
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var coordinateSignature: String = ""
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            
            // Arc positioning: endpoints at container edges, shallow arc (1/4 height)
            // Arc spans from 150° to 30° (shallow curve)
            let horizontalPadding: CGFloat = 20
            let arcRadius = (width / 2 - horizontalPadding) / 0.866
            let apexTargetY = height * 0.4
            let arcCenter = CGPoint(x: width / 2, y: apexTargetY + arcRadius)
            
            // Gradient scrolling tied to offsetMinutes
            // Make gradient much taller for smooth scrolling
            let gradientHeight = height * 30 // Very tall for smooth scrolling
            let normalized = max(0, min(1, (offsetMinutes - range.lowerBound) / (range.upperBound - range.lowerBound)))
            // The gradient stops go from location 0.0 to 1.0
            // When normalized=0: show location 0.0 at top (offset = 0)
            // When normalized=1: show location 1.0 at bottom (offset = gradientHeight - height)
            let scrollableHeight = gradientHeight - height
            // Calculate offset: move gradient UP by this amount
            // normalized=0 -> offset=0 (show top)
            // normalized=1 -> offset=scrollableHeight (show bottom)
            let gradientOffset = normalized * scrollableHeight
            
            ZStack {
                // Scrollable gradient background - covers entire card (only if not using external gradient)
                if !useExternalGradient {
                    GeometryReader { geo in
                        gradientBackground
                            .frame(width: geo.size.width, height: gradientHeight)
                            .offset(y: -gradientOffset)
                            .clipped()
                    }
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                
                // Shallow arc (1/4 height) with fading endpoints using Canvas
                Canvas { context, size in
                    let startAngle: Double = 150.0
                    let endAngle: Double = 30.0
                    let fadeLength: Double = 15.0 // degrees
                    let segments = 50
                    
                    for i in 0..<segments {
                        let t1 = Double(i) / Double(segments)
                        let t2 = Double(i + 1) / Double(segments)
                        
                        // Calculate fade opacity
                        let opacity: Double
                        if t1 < fadeLength / 120.0 {
                            opacity = t1 / (fadeLength / 120.0)
                        } else if t2 > 1.0 - (fadeLength / 120.0) {
                            opacity = (1.0 - t2) / (fadeLength / 120.0)
                        } else {
                            opacity = 1.0
                        }
                        
                        let angle1 = startAngle + t1 * (endAngle - startAngle)
                        let angle2 = startAngle + t2 * (endAngle - startAngle)
                        let radians1 = angle1 * .pi / 180.0
                        let radians2 = angle2 * .pi / 180.0
                        
                        let x1 = arcCenter.x + arcRadius * cos(radians1)
                        let y1 = arcCenter.y - arcRadius * sin(radians1)
                        let x2 = arcCenter.x + arcRadius * cos(radians2)
                        let y2 = arcCenter.y - arcRadius * sin(radians2)
                        
                        var linePath = Path()
                        linePath.move(to: CGPoint(x: x1, y: y1))
                        linePath.addLine(to: CGPoint(x: x2, y: y2))
                        
                        context.stroke(linePath, with: .color(.white.opacity(opacity)), lineWidth: 2)
                    }
                }
                .frame(width: width, height: height)
                .allowsHitTesting(false) // Don't block drag gestures
                
                // Sun sphere positioned on the arc
                let sunPosition = calculateSunPositionOnArc(
                    center: arcCenter,
                    radius: arcRadius,
                    offset: offsetMinutes
                )
                
                ZStack {
                    // Outer glow (reduced)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.2),
                                    Color.white.opacity(0.1),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 8,
                                endRadius: 20
                            )
                        )
                        .frame(width: 40, height: 40)
                    
                    // Sun sphere (more white, less glow)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white,
                                    Color.white.opacity(0.8)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 10
                            )
                        )
                        .frame(width: 22, height: 22)
                        .shadow(color: .white.opacity(0.4), radius: 4)
                }
                .position(sunPosition)
                
                // Content overlay
                VStack(alignment: .leading, spacing: 0) {
                    // Top section: Offset + Event name (left) and onset time (right)
                    HStack(alignment: .top) {
                        // Top left: Offset description above event name
                        VStack(alignment: .leading, spacing: 4) {
                            Text(offsetDescription)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                            Text(eventType.eventName)
                                .font(.title2.weight(.bold))
                                .foregroundColor(.white)
                        }
                        Spacer()
                        // Top right: Actual onset time
                        if let nextTime = nextEventTime {
                            Text(nextTime.formatted(date: .omitted, time: .shortened))
                                .font(.title3.weight(.semibold))
                                .foregroundColor(.white)
                        } else {
                            Text(estimatedTime)
                                .font(.title3.weight(.semibold))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    Spacer()
                    
                    // Bottom center: Event name above time(s)
                    HStack {
                        Spacer()
                        VStack(alignment: .center, spacing: 2) {
                            Text(eventType.eventName)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            if eventType == .sunrise {
                                if let sunrise = sunriseTime {
                                    Text(sunrise.formatted(date: .omitted, time: .shortened))
                                        .font(.headline.weight(.semibold))
                                        .foregroundColor(.white)
                                } else {
                                    Text(estimatedSunriseTime)
                                        .font(.headline.weight(.semibold))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            } else {
                                if let sunset = sunsetTime {
                                    Text(sunset.formatted(date: .omitted, time: .shortened))
                                        .font(.headline.weight(.semibold))
                                        .foregroundColor(.white)
                                } else {
                                    Text(estimatedSunsetTime)
                                        .font(.headline.weight(.semibold))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(.bottom, 20)
                }
                .frame(width: width, height: height)
                .allowsHitTesting(false) // Text overlays shouldn't block gestures
            }
            .contentShape(Rectangle()) // Make entire area tappable
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateOffsetFromDrag(
                            value.location,
                            center: arcCenter,
                            radius: arcRadius,
                            width: width,
                            height: height
                        )
                    }
            )
        }
        .aspectRatio(2.42, contentMode: .fit)
        .frame(maxHeight: 200)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onAppear {
            loadCoordinate()
        }
        .onChange(of: eventType) { _, _ in
            calculateNextEventTime()
        }
        .onChange(of: offsetMinutes) { _, _ in
            calculateNextEventTime()
        }
        .onChange(of: coordinateSignature) { _, _ in
            refreshSolarTimes()
        }
    }
    
    // MARK: - Gradient Background
    
    private var gradientBackground: some View {
        LinearGradient(
            gradient: Gradient(stops: Self.gradientStops(for: eventType)),
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    static func gradientStops(for eventType: SolarEvent) -> [Gradient.Stop] {
        var stops: [Gradient.Stop] = []
        
        if eventType == .sunrise {
            // Sunrise gradient: Golden hour persists until +30 min, then transitions to blue
            // -120 to -40 min: Deep night → Golden (starting to turn red)
            // -40 to 0 min: Golden → Red/Orange (peak at sunrise)
            // 0 to +30 min: Golden hour (keep golden/orange)
            // +30 to +60 min: Transition golden → light blue
            // +60 to +120 min: Light blue → Day blue → Afternoon blue (NO BLACK!)
            stops = [
                // -120 min: Deep night
                .init(color: Color(red: 0.043, green: 0.086, blue: 0.169), location: 0.0),      // #0B162B
                // -60 min: Pre-dawn, starting golden
                .init(color: Color(red: 0.102, green: 0.192, blue: 0.282), location: 0.25),   // #1A3148
                // -40 min: Golden, starting to turn red
                .init(color: Color(red: 0.949, green: 0.623, blue: 0.019), location: 0.4),    // #F29F05
                // At sunrise (0 min): Peak golden/orange
                .init(color: Color(red: 0.949, green: 0.529, blue: 0.019), location: 0.5),     // #F28705 (at sunrise)
                // +30 min: Still in golden hour
                .init(color: Color(red: 0.827, green: 0.4, blue: 0.15), location: 0.625),      // Warm golden
                // +60 min: Transitioning to blue
                .init(color: Color(red: 0.45, green: 0.55, blue: 0.65), location: 0.8),        // Sky blue
                // +120 min: Afternoon blue (NOT black!)
                .init(color: Color(red: 0.45, green: 0.6, blue: 0.7), location: 1.0)          // Day blue
            ]
        } else {
            // Sunset gradient: Light blue (before sunset) → Golden hour → Evening → Night
            stops = [
                // -120 min: Light blue (daytime)
                .init(color: Color(red: 0.45, green: 0.6, blue: 0.7), location: 0.0),          // Day blue
                // -60 min: Bright blue
                .init(color: Color(red: 0.5, green: 0.65, blue: 0.75), location: 0.25),        // Bright blue
                // -40 min: Transitioning from blue to golden
                .init(color: Color(red: 0.55, green: 0.65, blue: 0.7), location: 0.45),       // Blue-white
                // At sunset (0 min): Golden hour
                .init(color: Color(red: 0.7, green: 0.45, blue: 0.35), location: 0.5),         // Orange (at sunset)
                // +30 min: Still golden
                .init(color: Color(red: 0.85, green: 0.55, blue: 0.4), location: 0.625),       // Bright golden
                // +60 min: Evening transition
                .init(color: Color(red: 0.5, green: 0.35, blue: 0.38), location: 0.83),        // Evening red-orange
                // +120 min: Deep night
                .init(color: Color(red: 0.05, green: 0.08, blue: 0.15), location: 1.0)         // Deep night
            ]
        }
        
        return stops
    }
    
    // MARK: - Helper Properties
    
    private var offsetDescription: String {
        let minutes = Int(offsetMinutes)
        if minutes == 0 {
            return "At \(eventType.eventName.lowercased())"
        } else if minutes > 0 {
            return "\(minutes) min after"
        } else {
            return "\(abs(minutes)) min before"
        }
    }
    
    private var estimatedTime: String {
        "Calculating..."
    }
    
    private var estimatedSunriseTime: String {
        "6:00 AM"
    }
    
    private var estimatedSunsetTime: String {
        "6:00 PM"
    }
    
    // MARK: - Arc Drawing
    
    private func calculateSunPositionOnArc(
        center: CGPoint,
        radius: CGFloat,
        offset: Double
    ) -> CGPoint {
        // Map offset (-120 to +120) to arc angle (150° to 30°)
        let normalized = max(0, min(1, (offset - range.lowerBound) / (range.upperBound - range.lowerBound)))
        // Arc spans from 150° to 30° (120° total)
        let startAngle: Double = 150.0
        let endAngle: Double = 30.0
        let angleRange = endAngle - startAngle
        let angle = startAngle + (normalized * angleRange)
        let radians = angle * .pi / 180.0
        
        let x = center.x + radius * cos(radians)
        let y = center.y - radius * sin(radians) // Negative because Y increases downward
        return CGPoint(x: x, y: y)
    }
    
    private func updateOffsetFromDrag(
        _ location: CGPoint,
        center: CGPoint,
        radius: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) {
        // Use angle-based dragging along the arc for smooth sliding
        // Calculate angle from center to drag location
        let dx = location.x - center.x
        let dy = center.y - location.y // Invert Y because Y increases downward
        let angleRadians = atan2(dy, dx)
        let angleDegrees = angleRadians * 180.0 / .pi
        // Normalize to 0-360
        let normalizedAngle = angleDegrees < 0 ? angleDegrees + 360 : angleDegrees
        
        // Arc spans from 150° to 30° going clockwise (negative direction)
        // Path: 150° (left) -> 120° -> 90° (top) -> 60° -> 30° (right)
        let startAngle: Double = 150.0  // Left endpoint
        let endAngle: Double = 30.0     // Right endpoint
        
        // The arc goes clockwise from 150° to 30°
        // So angles go from 150° down to 30° (decreasing)
        // Map the drag angle to this range
        let normalized: Double
        
        if normalizedAngle >= startAngle {
            // Angle is >= 150°, which is beyond the left endpoint
            // Clamp to start (left endpoint)
            normalized = 0.0
        } else if normalizedAngle <= endAngle {
            // Angle is <= 30°, which is at or beyond the right endpoint
            // Clamp to end (right endpoint)
            normalized = 1.0
        } else {
            // Angle is between 30° and 150° - this is ON the arc (including the top at 90°)
            // Map: angle goes from 150° down to 30° (120° range)
            // So: normalized = (150° - angle) / (150° - 30°) = (150° - angle) / 120°
            normalized = (startAngle - normalizedAngle) / (startAngle - endAngle)
        }
        
        // Clamp and map to offset range
        let clampedNormalized = max(0, min(1, normalized))
        let newOffset = range.lowerBound + (clampedNormalized * (range.upperBound - range.lowerBound))
        offsetMinutes = newOffset
    }
    
    // MARK: - Solar Time Calculation
    
    private func loadCoordinate() {
        Task {
            let store = AutomationStore.shared
            print("📍 SolarOffsetArcSlider: Loading coordinate...")
            
            // Try to get user's actual location, fallback to San Francisco
            let userCoordinate = await store.currentCoordinate() ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
            print("✅ Using location: \(userCoordinate.latitude), \(userCoordinate.longitude)")
            
            await MainActor.run {
                self.coordinate = userCoordinate
                self.coordinateSignature = "\(userCoordinate.latitude),\(userCoordinate.longitude)"
                // Calculate times after setting coordinate (on MainActor)
                calculateSolarTimes()
            }
        }
    }
    
    private func refreshSolarTimes() {
        calculateSolarTimes()
        calculateNextEventTime()
    }
    
    private func calculateSolarTimes() {
        guard let currentCoordinate = coordinate else {
            print("⚠️ SolarOffsetArcSlider: No coordinate available")
            return
        }
        
        let store = AutomationStore.shared
        let baseDate = Date()
        
        print("🌅 Calculating solar times for \(eventType.eventName) at \(currentCoordinate.latitude), \(currentCoordinate.longitude)")
        
        // ALWAYS calculate BOTH sunrise and sunset times (so they're available for display)
        sunriseTime = store.resolveSolarTriggerDate(
            event: .sunrise,
            coordinate: currentCoordinate,
            date: baseDate,
            offsetMinutes: 0
        )
        print("🌅 Sunrise time: \(sunriseTime?.formatted(date: .omitted, time: .shortened) ?? "nil")")
        
        sunsetTime = store.resolveSolarTriggerDate(
            event: .sunset,
            coordinate: currentCoordinate,
            date: baseDate,
            offsetMinutes: 0
        )
        print("🌇 Sunset time: \(sunsetTime?.formatted(date: .omitted, time: .shortened) ?? "nil")")
        
        // Calculate next event time based on current eventType and offset
        nextEventTime = store.resolveSolarTriggerDate(
            event: eventType,
            coordinate: currentCoordinate,
            date: baseDate,
            offsetMinutes: Int(offsetMinutes)
        )
        print("⏰ Next event time (\(eventType.eventName)): \(nextEventTime?.formatted(date: .omitted, time: .shortened) ?? "nil")")
    }
    
    private func calculateNextEventTime() {
        guard let currentCoordinate = coordinate else { return }
        
        let store = AutomationStore.shared
        nextEventTime = store.resolveSolarTriggerDate(
            event: eventType,
            coordinate: currentCoordinate,
            date: Date(),
            offsetMinutes: Int(offsetMinutes)
        )
    }
}

// MARK: - Arc Shape with Fading Endpoints

struct ArcShapeWithFade: Shape {
    let center: CGPoint
    let radius: CGFloat
    let containerSize: CGSize
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Arc spans from 150° to 30° (120° total)
        let startAngle: Double = 150.0
        let endAngle: Double = 30.0
        let segments = 50
        
        for i in 0...segments {
            let t = Double(i) / Double(segments)
            let baseAngle = startAngle + t * (endAngle - startAngle)
            
            let radians = baseAngle * .pi / 180.0
            let x = center.x + radius * cos(radians)
            let y = center.y - radius * sin(radians)
            let point = CGPoint(x: x, y: y)
            
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        
        return path
            .strokedPath(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
}

// MARK: - Extensions

extension SolarEvent {
    var eventName: String {
        switch self {
        case .sunrise: return "Sunrise"
        case .sunset: return "Sunset"
        }
    }
}

// MARK: - AutomationStore Extension

extension AutomationStore {
    func resolveSolarTriggerDate(
        event: SolarEvent,
        coordinate: CLLocationCoordinate2D,
        date: Date,
        offsetMinutes: Int
    ) async -> Date? {
        let timeZone = TimeZone.current
        return SunriseSunsetCalculator.nextEventDate(
            event: event,
            coordinate: coordinate,
            referenceDate: date,
            offsetMinutes: offsetMinutes,
            timeZone: timeZone
        )
    }
}

