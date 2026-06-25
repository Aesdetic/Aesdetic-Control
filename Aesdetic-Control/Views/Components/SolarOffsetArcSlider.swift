import SwiftUI
import CoreLocation

struct SolarOffsetArcSlider: View {
    @Binding var offsetMinutes: Double
    let eventType: SolarEvent
    let device: WLEDDevice
    var disableClipping: Bool = false
    var useExternalGradient: Bool = false
    var maintainAspectRatio: Bool = true
    
    private let range: ClosedRange<Double> = Double(SolarTrigger.minOnDeviceOffsetMinutes)...Double(SolarTrigger.maxOnDeviceOffsetMinutes)
    
    @State private var sunriseTime: Date?
    @State private var sunsetTime: Date?
    @State private var nextEventTime: Date?
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var solarTimeZone: TimeZone = .current
    @State private var coordinateSignature: String = ""
    @State private var locationUnavailable: Bool = false

    private struct SolarStar: Identifiable {
        let id: Int
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let opacity: Double
    }

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

                // Sun sphere positioned on the arc
                let sunPosition = calculateSunPositionOnArc(
                    center: arcCenter,
                    radius: arcRadius,
                    offset: offsetMinutes
                )

                nightStarsOverlay(width: width, height: height)
                    .opacity(nightSkyOpacity(normalizedOffset: normalized))
                    .allowsHitTesting(false)

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
                        
                        context.stroke(linePath, with: .color(.white.opacity(opacity * 0.68)), lineWidth: 1.6)
                    }
                }
                .frame(width: width, height: height)
                .allowsHitTesting(false) // Don't block drag gestures

                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.18),
                                    Color.white.opacity(0.06),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 8,
                                endRadius: 18
                            )
                        )
                        .frame(width: 36, height: 36)
                    
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.96),
                                    Color.white.opacity(0.74)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 10
                            )
                        )
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.55), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2)
                }
                .position(sunPosition)
                
                // Content overlay
                VStack(alignment: .leading, spacing: 0) {
                    // Top section: Offset + Event name (left) and onset time (right)
                    HStack(alignment: .top) {
                        // Top left: Offset description above event name
                        VStack(alignment: .leading, spacing: 4) {
                            Text(offsetDescription)
                                .font(AppTypography.style(.subheadline))
                                .foregroundColor(.white.opacity(0.9))
                            Text(eventType.eventName)
                                .font(AppTypography.style(.title2, weight: .bold))
                                .foregroundColor(.white)
                        }
                        Spacer()
                        // Top right: Actual onset time
                        if let nextTime = nextEventTime {
                            Text(nextTime.formatted(date: .omitted, time: .shortened))
                                .font(AppTypography.style(.title3, weight: .semibold))
                                .foregroundColor(.white)
                        } else {
                            Text(estimatedTime)
                                .font(AppTypography.style(.title3, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    
                    Spacer()
                    
                    // Bottom center: Event name above time(s)
                    HStack {
                        Spacer()
                        VStack(alignment: .center, spacing: 2) {
                            Text(eventType.eventName)
                                .font(AppTypography.style(.caption))
                                .foregroundColor(.white.opacity(0.7))
                            if eventType == .sunrise {
                                if let sunrise = sunriseTime {
                                    Text(sunrise.formatted(date: .omitted, time: .shortened))
                                        .font(AppTypography.style(.headline, weight: .semibold))
                                        .foregroundColor(.white)
                                } else {
                                    Text(estimatedSunriseTime)
                                        .font(AppTypography.style(.headline, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            } else {
                                if let sunset = sunsetTime {
                                    Text(sunset.formatted(date: .omitted, time: .shortened))
                                        .font(AppTypography.style(.headline, weight: .semibold))
                                        .foregroundColor(.white)
                                } else {
                                    Text(estimatedSunsetTime)
                                        .font(AppTypography.style(.headline, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(.bottom, 4)
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
        .modifier(SolarOffsetLayoutModifier(maintainAspectRatio: maintainAspectRatio))
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
        .onChange(of: device.id) { _, _ in
            loadCoordinate()
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
            stops = [
                .init(color: Color(red: 0.050, green: 0.075, blue: 0.150), location: 0.0),
                .init(color: Color(red: 0.110, green: 0.185, blue: 0.285), location: 0.22),
                .init(color: Color(red: 0.425, green: 0.345, blue: 0.430), location: 0.36),
                .init(color: Color(red: 0.780, green: 0.470, blue: 0.350), location: 0.48),
                .init(color: Color(red: 0.940, green: 0.650, blue: 0.390), location: 0.58),
                .init(color: Color(red: 0.635, green: 0.700, blue: 0.740), location: 0.78),
                .init(color: Color(red: 0.455, green: 0.650, blue: 0.760), location: 1.0)
            ]
        } else {
            stops = [
                .init(color: Color(red: 0.455, green: 0.645, blue: 0.750), location: 0.0),
                .init(color: Color(red: 0.625, green: 0.730, blue: 0.775), location: 0.22),
                .init(color: Color(red: 0.820, green: 0.675, blue: 0.500), location: 0.42),
                .init(color: Color(red: 0.805, green: 0.445, blue: 0.340), location: 0.54),
                .init(color: Color(red: 0.565, green: 0.330, blue: 0.465), location: 0.68),
                .init(color: Color(red: 0.210, green: 0.180, blue: 0.330), location: 0.84),
                .init(color: Color(red: 0.050, green: 0.070, blue: 0.145), location: 1.0)
            ]
        }
        
        return stops
    }

    @ViewBuilder
    private func nightStarsOverlay(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            ForEach(Self.starField) { star in
                Circle()
                    .fill(Color.white.opacity(star.opacity))
                    .frame(width: star.size, height: star.size)
                    .position(x: width * star.x, y: height * star.y)
            }
        }
        .frame(width: width, height: height)
    }

    private func nightSkyOpacity(normalizedOffset: Double) -> Double {
        switch eventType {
        case .sunrise:
            return smoothFade(from: 0.36, to: 0.12, value: normalizedOffset) * 0.92
        case .sunset:
            return smoothFade(from: 0.70, to: 0.92, value: normalizedOffset) * 0.92
        }
    }

    private func smoothFade(from start: Double, to end: Double, value: Double) -> Double {
        let progress: Double
        if end >= start {
            progress = min(1, max(0, (value - start) / (end - start)))
        } else {
            progress = min(1, max(0, (value - end) / (start - end)))
        }
        let eased = progress * progress * (3 - 2 * progress)
        return end >= start ? eased : 1 - eased
    }

    private static let starField: [SolarStar] = [
        SolarStar(id: 0, x: 0.12, y: 0.20, size: 1.8, opacity: 0.58),
        SolarStar(id: 1, x: 0.23, y: 0.34, size: 1.2, opacity: 0.42),
        SolarStar(id: 2, x: 0.32, y: 0.17, size: 1.4, opacity: 0.46),
        SolarStar(id: 3, x: 0.48, y: 0.28, size: 1.1, opacity: 0.38),
        SolarStar(id: 4, x: 0.64, y: 0.19, size: 1.6, opacity: 0.52),
        SolarStar(id: 5, x: 0.78, y: 0.33, size: 1.2, opacity: 0.40),
        SolarStar(id: 6, x: 0.88, y: 0.22, size: 1.5, opacity: 0.48),
        SolarStar(id: 7, x: 0.18, y: 0.48, size: 1.0, opacity: 0.32),
        SolarStar(id: 8, x: 0.72, y: 0.47, size: 1.0, opacity: 0.30)
    ]

    // MARK: - Helper Properties
    
    private var offsetDescription: String {
        let minutes = SolarTrigger.clampOnDeviceOffset(Int(offsetMinutes.rounded()))
        if minutes == 0 {
            return "At \(eventType.eventName.lowercased())"
        } else if minutes > 0 {
            return "\(minutes) min after"
        } else {
            return "\(abs(minutes)) min before"
        }
    }
    
    private var estimatedTime: String {
        locationUnavailable ? "Location unavailable" : "Calculating..."
    }
    
    private var estimatedSunriseTime: String {
        locationUnavailable ? "--:--" : "6:00 AM"
    }
    
    private var estimatedSunsetTime: String {
        locationUnavailable ? "--:--" : "6:00 PM"
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
            #if DEBUG
            print("📍 SolarOffsetArcSlider: Loading coordinate...")
            #endif
            
            // Prefer WLED-configured if.ntp location/timezone, then fall back to iOS location.
            if let reference = await store.currentSolarReference(for: device) {
                #if DEBUG
                print("✅ Using location: \(reference.coordinate.latitude), \(reference.coordinate.longitude) tz=\(reference.timeZone.identifier)")
                #endif
                
                await MainActor.run {
                    self.coordinate = reference.coordinate
                    self.solarTimeZone = reference.timeZone
                    self.coordinateSignature = "\(reference.coordinate.latitude),\(reference.coordinate.longitude),\(reference.timeZone.identifier)"
                    self.locationUnavailable = false
                    // Calculate times after setting coordinate (on MainActor)
                    calculateSolarTimes()
                }
            } else {
                await MainActor.run {
                    self.coordinate = nil
                    self.solarTimeZone = .current
                    self.coordinateSignature = ""
                    self.locationUnavailable = true
                    self.sunriseTime = nil
                    self.sunsetTime = nil
                    self.nextEventTime = nil
                }
            }
        }
    }
    
    private func refreshSolarTimes() {
        calculateSolarTimes()
        calculateNextEventTime()
    }
    
    private func calculateSolarTimes() {
        guard let currentCoordinate = coordinate else {
            #if DEBUG
            print("⚠️ SolarOffsetArcSlider: No coordinate available")
            #endif
            return
        }
        
        let store = AutomationStore.shared
        let baseDate = Date()
        
        #if DEBUG
        print("🌅 Calculating solar times for \(eventType.eventName) at \(currentCoordinate.latitude), \(currentCoordinate.longitude)")
        #endif
        
        // ALWAYS calculate BOTH sunrise and sunset times (so they're available for display)
        sunriseTime = store.resolveSolarTriggerDate(
            event: .sunrise,
            coordinate: currentCoordinate,
            date: baseDate,
            offsetMinutes: 0,
            timeZone: solarTimeZone
        )
        #if DEBUG
        print("🌅 Sunrise time: \(sunriseTime?.formatted(date: .omitted, time: .shortened) ?? "nil")")
        #endif
        
        sunsetTime = store.resolveSolarTriggerDate(
            event: .sunset,
            coordinate: currentCoordinate,
            date: baseDate,
            offsetMinutes: 0,
            timeZone: solarTimeZone
        )
        #if DEBUG
        print("🌇 Sunset time: \(sunsetTime?.formatted(date: .omitted, time: .shortened) ?? "nil")")
        #endif
        
        // Calculate next event time based on current eventType and offset
        nextEventTime = store.resolveSolarTriggerDate(
            event: eventType,
            coordinate: currentCoordinate,
            date: baseDate,
            offsetMinutes: SolarTrigger.clampOnDeviceOffset(Int(offsetMinutes.rounded())),
            timeZone: solarTimeZone
        )
        #if DEBUG
        print("⏰ Next event time (\(eventType.eventName)): \(nextEventTime?.formatted(date: .omitted, time: .shortened) ?? "nil")")
        #endif
    }
    
    private func calculateNextEventTime() {
        guard let currentCoordinate = coordinate else { return }
        
        let store = AutomationStore.shared
        nextEventTime = store.resolveSolarTriggerDate(
            event: eventType,
            coordinate: currentCoordinate,
            date: Date(),
            offsetMinutes: SolarTrigger.clampOnDeviceOffset(Int(offsetMinutes.rounded())),
            timeZone: solarTimeZone
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

private struct SolarOffsetLayoutModifier: ViewModifier {
    let maintainAspectRatio: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if maintainAspectRatio {
            content
                .aspectRatio(2.42, contentMode: .fit)
                .frame(maxHeight: 200)
        } else {
            content
        }
    }
}
