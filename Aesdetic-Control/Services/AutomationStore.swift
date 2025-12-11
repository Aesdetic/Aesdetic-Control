import Foundation
import Combine
import os.log
import CoreLocation

@MainActor
class AutomationStore: ObservableObject {
    static let shared = AutomationStore()
    
    @Published var automations: [Automation] = []
    @Published private(set) var upcomingAutomationInfo: (automation: Automation, date: Date)?
    
    private let fileURL: URL
    private var schedulerTimer: Timer?
    private let logger = Logger(subsystem: "com.aesdetic.control", category: "AutomationStore")
    private let scenesStore = ScenesStore.shared
    private let presetsStore = PresetsStore.shared
    private let viewModel = DeviceControlViewModel.shared
    private let apiService = WLEDAPIService.shared
    private let locationProvider = LocationProvider()
    private var solarCache: [SolarCacheKey: Date] = [:]
    
    private init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = documentsPath.appendingPathComponent("automations.json")
        load()
        scheduleNext()
    }
    
    deinit {
        schedulerTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    func add(_ automation: Automation) {
        var record = automation
        record.updatedAt = Date()
        automations.append(record)
        save()
        scheduleNext()
        logger.info("Added automation: \(record.name)")
    }
    
    func update(_ automation: Automation) {
        guard let index = automations.firstIndex(where: { $0.id == automation.id }) else { return }
        var record = automation
        record.updatedAt = Date()
        // Create a new array to trigger @Published change notification
        var updated = automations
        updated[index] = record
        automations = updated
        save()
        scheduleNext()
        logger.info("Updated automation: \(record.name)")
    }
    
    func delete(id: UUID) {
        guard let index = automations.firstIndex(where: { $0.id == id }) else { return }
        let automation = automations.remove(at: index)
        save()
        scheduleNext()
        logger.info("Deleted automation: \(automation.name)")
    }
    
    func applyAutomation(_ automation: Automation) {
        logger.info("Applying automation: \(automation.name)")
        
        let devices = viewModel.devices.filter { automation.targets.deviceIds.contains($0.id) }
        guard !devices.isEmpty else {
            logger.error("No devices found for automation \(automation.name)")
            return
        }
        
        let allowPartial = automation.targets.allowPartialFailure
        let nameLookup = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0.name) })
        
        Task { @MainActor in
            var failedIds: [String] = []
            let retryAttempts = automation.targets.allowPartialFailure ? 0 : 1
            await withTaskGroup(of: (String, Bool).self) { group in
                for device in devices {
                    group.addTask { [weak self] in
                        guard let self else { return (device.id, false) }
                        let success = await self.runActionWithRetry(
                            automation.action,
                            automation: automation,
                            on: device,
                            retryAttempts: retryAttempts
                        )
                        return (device.id, success)
                    }
                }
                
                for await result in group {
                    if !result.1 {
                        failedIds.append(result.0)
                        if !allowPartial {
                            group.cancelAll()
                        }
                    }
                }
            }
            
            if failedIds.count == devices.count {
                let names = failedIds.compactMap { nameLookup[$0] ?? $0 }
                logger.error("Automation \(automation.name) failed for devices: \(names.joined(separator: ", "))")
                return
            }
            
            var updated = automation
            updated.lastTriggered = Date()
            update(updated)
            
            if !failedIds.isEmpty {
                let names = failedIds.compactMap { nameLookup[$0] ?? $0 }
                logger.error("Automation \(automation.name) partially failed for devices: \(names.joined(separator: ", "))")
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func scheduleNext() {
        schedulerTimer?.invalidate()
        upcomingAutomationInfo = nil
        guard !automations.isEmpty else { return }
        Task { @MainActor in
            guard let (nextAutomation, nextDate) = await resolveNextAutomation(referenceDate: Date()) else { return }
            upcomingAutomationInfo = (nextAutomation, nextDate)
            scheduleTimer(for: nextAutomation, fireDate: nextDate)
        }
    }
    
    private func scheduleTimer(for automation: Automation, fireDate: Date) {
        schedulerTimer?.invalidate()
        let interval = max(1.0, fireDate.timeIntervalSince(Date()))
        logger.info("Scheduling next automation '\(automation.name)' in \(interval) seconds")
        schedulerTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.triggerAutomation(automation)
            }
        }
    }
    
    private func triggerAutomation(_ automation: Automation) {
        logger.info("Triggering automation: \(automation.name)")
        applyAutomation(automation)
        scheduleNext()
    }
    
    private func resolveNextAutomation(referenceDate: Date) async -> (Automation, Date)? {
        var best: (Automation, Date)?
        for automation in automations where automation.enabled {
            if let nextDate = automation.nextTriggerDate(referenceDate: referenceDate) {
                if best == nil || nextDate < best!.1 {
                    best = (automation, nextDate)
                }
                continue
            }
            
            if let solarDate = await resolveSolarTrigger(for: automation, referenceDate: referenceDate) {
                if best == nil || solarDate < best!.1 {
                    best = (automation, solarDate)
                }
            }
        }
        return best
    }
    
    private func resolveSolarTrigger(for automation: Automation, referenceDate: Date) async -> Date? {
        switch automation.trigger {
        case .sunrise(let solar):
            return await computeSolarDate(event: .sunrise, trigger: solar, referenceDate: referenceDate)
        case .sunset(let solar):
            return await computeSolarDate(event: .sunset, trigger: solar, referenceDate: referenceDate)
        default:
            return nil
        }
    }
    
    func computeSolarDate(event: SolarEvent, trigger: SolarTrigger, referenceDate: Date) async -> Date? {
        guard let coordinate = await coordinate(for: trigger.location) else {
            logger.error("Missing coordinate for solar automation")
            return nil
        }
        
        let cacheKey = SolarCacheKey(event: event, coordinate: coordinate, date: Calendar.current.startOfDay(for: referenceDate), offsetMinutes: trigger.offset)
        if let cached = solarCache[cacheKey], cached > referenceDate {
            return cached
        }
        
        let offsetMinutes: Int
        switch trigger.offset {
        case .minutes(let value):
            offsetMinutes = value
        }
        
        guard let eventDate = SunriseSunsetCalculator.nextEventDate(
            event: event,
            coordinate: coordinate,
            referenceDate: referenceDate,
            offsetMinutes: offsetMinutes,
            timeZone: TimeZone.current
        ) else {
            return nil
        }
        solarCache[cacheKey] = eventDate
        return eventDate
    }
    
    /// Public API to get user's current coordinate
    /// Returns nil if permission denied or location unavailable
    func currentCoordinate() async -> CLLocationCoordinate2D? {
        do {
            return try await locationProvider.currentCoordinate()
        } catch {
            logger.warning("Location unavailable: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Public API for components to resolve solar trigger dates
    func resolveSolarTriggerDate(
        event: SolarEvent,
        coordinate: CLLocationCoordinate2D,
        date: Date,
        offsetMinutes: Int
    ) -> Date? {
        let result = SunriseSunsetCalculator.nextEventDate(
            event: event,
            coordinate: coordinate,
            referenceDate: date,
            offsetMinutes: offsetMinutes,
            timeZone: TimeZone.current
        )
        print("🔍 resolveSolarTriggerDate: \(event) at \(coordinate.latitude), \(coordinate.longitude) offset \(offsetMinutes) = \(result?.formatted(date: .omitted, time: .shortened) ?? "nil")")
        return result
    }
    
    private func coordinate(for source: SolarTrigger.LocationSource) async -> CLLocationCoordinate2D? {
        switch source {
        case .manual(let lat, let lon):
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        case .followDevice:
            do {
                return try await locationProvider.currentCoordinate()
            } catch {
                logger.error("Failed to fetch device location: \(error.localizedDescription)")
                return nil
            }
        }
    }
    
    private func perform(action: AutomationAction, automation: Automation, on device: WLEDDevice) async -> Bool {
        switch action {
        case .scene(let payload):
            guard let scene = scenesStore.scenes.first(where: { $0.id == payload.sceneId }) else {
                logger.error("Scene \(payload.sceneId) missing for automation \(automation.name)")
                return false
            }
            var sceneCopy = scene
            sceneCopy.deviceId = device.id
            if let override = payload.brightnessOverride {
                sceneCopy.brightness = override
            }
            await viewModel.applyScene(sceneCopy, to: device)
            return true
            
        case .preset(let payload):
            do {
                _ = try await apiService.applyPreset(payload.presetId, to: device, transition: nil)
            } catch {
                logger.error("Failed to apply preset \(payload.presetId) for automation \(automation.name): \(error.localizedDescription)")
                return false
            }
            return true
            
        case .gradient(let payload):
            let gradient = resolveGradientPayload(payload, device: device)
            if payload.durationSeconds > 0.5 {
                await viewModel.runSimpleGradientFade(
                    for: device,
                    targetGradient: gradient,
                    targetBrightness: payload.brightness,
                    durationSeconds: payload.durationSeconds
                )
            } else {
                let ledCount = device.state?.segments.first?.len ?? 120
                await viewModel.applyGradientStopsAcrossStrip(
                    device,
                    stops: gradient.stops,
                    ledCount: ledCount,
                    disableActiveEffect: true,
                    interpolation: gradient.interpolation,
                    brightness: payload.brightness,
                    on: true
                )
                await viewModel.updateDeviceBrightness(device, brightness: payload.brightness)
            }
            return true
            
        case .transition(let payload):
            let resolved = resolveTransitionPayload(payload, device: device)
            await viewModel.runAutomationTransition(
                for: device,
                startGradient: resolved.startGradient,
                startBrightness: resolved.startBrightness,
                endGradient: resolved.endGradient,
                endBrightness: resolved.endBrightness,
                durationSeconds: resolved.durationSeconds
            )
            return true
            
        case .effect(let payload):
            let resolved = resolveEffectPayload(payload, device: device)
            let gradient = resolved.gradient ?? defaultGradient(for: device)
            await viewModel.updateDeviceBrightness(device, brightness: resolved.brightness)
            await viewModel.applyColorSafeEffect(
                resolved.effectId,
                with: gradient,
                segmentId: 0,
                device: device
            )
            return true
            
        case .directState(let payload):
            let stops = [
                GradientStop(position: 0.0, hexColor: payload.colorHex),
                GradientStop(position: 1.0, hexColor: payload.colorHex)
            ]
            let ledCount = device.state?.segments.first?.len ?? 120
            await viewModel.applyGradientStopsAcrossStrip(
                device,
                stops: stops,
                ledCount: ledCount,
                disableActiveEffect: true,
                brightness: payload.brightness,
                on: true
            )
            await viewModel.updateDeviceBrightness(device, brightness: payload.brightness)
            return true
        }
    }
    
    private func runActionWithRetry(
        _ action: AutomationAction,
        automation: Automation,
        on device: WLEDDevice,
        retryAttempts: Int
    ) async -> Bool {
        if await perform(action: action, automation: automation, on: device) {
            return true
        }
        guard retryAttempts > 0 else { return false }
        try? await Task.sleep(nanoseconds: 500_000_000)
        return await runActionWithRetry(action, automation: automation, on: device, retryAttempts: retryAttempts - 1)
    }
    
    private func resolveGradientPayload(_ payload: GradientActionPayload, device: WLEDDevice) -> LEDGradient {
        if let presetId = payload.presetId,
           let preset = presetsStore.colorPreset(id: presetId) {
            return LEDGradient(
                stops: preset.gradientStops,
                interpolation: payload.gradient.interpolation
            )
        }
        return payload.gradient
    }
    
    private func resolveTransitionPayload(_ payload: TransitionActionPayload, device: WLEDDevice) -> TransitionActionPayload {
        guard let presetId = payload.presetId,
              let preset = presetsStore.transitionPreset(id: presetId) else {
            return payload
        }
        return TransitionActionPayload(
            startGradient: preset.gradientA,
            startBrightness: preset.brightnessA,
            endGradient: preset.gradientB,
            endBrightness: preset.brightnessB,
            durationSeconds: payload.durationSeconds > 0 ? payload.durationSeconds : preset.durationSec,
            shouldLoop: payload.shouldLoop,
            presetId: presetId,
            presetName: preset.name
        )
    }
    
    private func resolveEffectPayload(_ payload: EffectActionPayload, device: WLEDDevice) -> EffectActionPayload {
        guard let presetId = payload.presetId,
              let preset = presetsStore.effectPreset(id: presetId) else {
            return payload
        }
        
        var gradient = payload.gradient
        if let presetStops = preset.gradientStops, !presetStops.isEmpty {
            gradient = LEDGradient(
                stops: presetStops,
                interpolation: preset.gradientInterpolation ?? gradient?.interpolation ?? .linear
            )
        }
        
        return EffectActionPayload(
            effectId: preset.effectId,
            effectName: preset.name,
            gradient: gradient,
            speed: preset.speed ?? payload.speed,
            intensity: preset.intensity ?? payload.intensity,
            paletteId: preset.paletteId ?? payload.paletteId,
            brightness: preset.brightness,
            presetId: presetId,
            presetName: preset.name
        )
    }
    
    private func defaultGradient(for device: WLEDDevice) -> LEDGradient {
        let hex = device.currentColor.toHex()
        return LEDGradient(stops: [
            GradientStop(position: 0.0, hexColor: hex),
            GradientStop(position: 1.0, hexColor: hex)
        ])
    }
    
    private func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            do {
                automations = try JSONDecoder().decode([Automation].self, from: data)
                logger.info("Loaded \(self.automations.count) automations")
            } catch {
                logger.error("Failed to decode automations, attempting legacy migration: \(error.localizedDescription)")
                automations = try migrateLegacyAutomations(from: data)
                save()
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == 260 {
                logger.debug("No automations file found (first launch) - will create on save")
            } else {
                logger.error("Failed to load automations: \(error.localizedDescription)")
            }
            automations = []
        }
    }
    
    private func migrateLegacyAutomations(from data: Data) throws -> [Automation] {
        let legacyRecords = try JSONDecoder().decode([LegacyAutomation].self, from: data)
        return legacyRecords.map { $0.toModern() }
    }
    
    private func save() {
        do {
            let data = try JSONEncoder().encode(automations)
            try data.write(to: fileURL)
            logger.info("Saved \(self.automations.count) automations")
        } catch {
            logger.error("Failed to save automations: \(error.localizedDescription)")
        }
    }
}

// MARK: - Legacy Model Migration

private struct LegacyAutomation: Codable {
    let id: UUID
    var name: String
    var enabled: Bool
    var time: String
    var weekdays: [Bool]
    var sceneId: UUID
    var deviceId: String
    var createdAt: Date
    var lastTriggered: Date?
    
    func toModern() -> Automation {
        let trigger = AutomationTrigger.specificTime(
            TimeTrigger(
                time: time,
                weekdays: weekdays,
                timezoneIdentifier: TimeZone.current.identifier
            )
        )
        let action = AutomationAction.scene(
            SceneActionPayload(
                sceneId: sceneId,
                sceneName: nil,
                brightnessOverride: nil
            )
        )
        let targets = AutomationTargets(deviceIds: [deviceId])
        return Automation(
            id: id,
            name: name,
            enabled: enabled,
            createdAt: createdAt,
            updatedAt: createdAt,
            lastTriggered: lastTriggered,
            trigger: trigger,
            action: action,
            targets: targets,
            metadata: AutomationMetadata()
        )
    }
}

// MARK: - Location Provider & Solar Calculations

private final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, Error>?
    private var cachedCoordinate: CLLocationCoordinate2D?
    private var lastUpdate: Date?
    
    // UserDefaults keys for persistent location storage
    private let latitudeKey = "com.aesdetic.cachedLatitude"
    private let longitudeKey = "com.aesdetic.cachedLongitude"
    private let lastUpdateKey = "com.aesdetic.lastLocationUpdate"
    
    override init() {
        super.init()
        manager.delegate = self
        // Use reduced accuracy for city-level location (~10km radius)
        // Perfect for sunrise/sunset, more privacy-friendly
        manager.desiredAccuracy = kCLLocationAccuracyReduced
        
        // Load cached location from UserDefaults (survives app restarts)
        loadCachedLocation()
    }
    
    private func loadCachedLocation() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: latitudeKey) != nil,
              defaults.object(forKey: longitudeKey) != nil else {
            return
        }
        
        let latitude = defaults.double(forKey: latitudeKey)
        let longitude = defaults.double(forKey: longitudeKey)
        
        if let timestamp = defaults.object(forKey: lastUpdateKey) as? Date {
            cachedCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            lastUpdate = timestamp
        }
    }
    
    private func saveCachedLocation() {
        guard let coordinate = cachedCoordinate, let update = lastUpdate else { return }
        
        let defaults = UserDefaults.standard
        defaults.set(coordinate.latitude, forKey: latitudeKey)
        defaults.set(coordinate.longitude, forKey: longitudeKey)
        defaults.set(update, forKey: lastUpdateKey)
    }
    
    func currentCoordinate() async throws -> CLLocationCoordinate2D {
        // Cache location for 30 days since lamps don't move
        // Only re-check if cache is stale or app restarts in new location
        if let coordinate = cachedCoordinate, let lastUpdate, Date().timeIntervalSince(lastUpdate) < 2_592_000 { // 30 days
            print("📍 Using cached location: \(coordinate.latitude), \(coordinate.longitude)")
            return coordinate
        }
        
        // Check authorization status before creating continuation
        switch manager.authorizationStatus {
        case .denied, .restricted:
            print("❌ Location permission denied")
            throw NSError(domain: kCLErrorDomain, code: CLError.denied.rawValue)
        case .notDetermined:
            print("❓ Location permission not determined - requesting...")
            manager.requestWhenInUseAuthorization()
            // Wait a bit for the permission dialog to be dismissed
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        default:
            break
        }
        
        // Now request location
        print("📍 Requesting location...")
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        print("🔐 Location authorization changed: \(manager.authorizationStatus.rawValue)")
        // Note: We no longer automatically request location here
        // The currentCoordinate() function will handle it after permission is granted
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            print("❌ No location in update")
            return
        }
        print("✅ Location updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        cachedCoordinate = location.coordinate
        lastUpdate = Date()
        saveCachedLocation() // Persist to UserDefaults
        continuation?.resume(returning: location.coordinate)
        continuation = nil
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location error: \(error.localizedDescription)")
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

public enum SolarEvent: Hashable {
    case sunrise
    case sunset
}

public enum SunriseSunsetCalculator {
    public static func nextEventDate(
        event: SolarEvent,
        coordinate: CLLocationCoordinate2D,
        referenceDate: Date,
        offsetMinutes: Int,
        timeZone: TimeZone
    ) -> Date? {
        let calendar = Calendar(identifier: .gregorian)
        for offset in 0...1 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: referenceDate),
                  let baseEvent = eventDate(on: date, event: event, coordinate: coordinate, timeZone: timeZone) else {
                continue
            }
            let adjusted = baseEvent.addingTimeInterval(Double(offsetMinutes) * 60)
            if adjusted > referenceDate {
                return adjusted
            }
        }
        return nil
    }
    
    private static func eventDate(
        on date: Date,
        event: SolarEvent,
        coordinate: CLLocationCoordinate2D,
        timeZone: TimeZone
    ) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) else {
            return nil
        }
        
        let zenith = 90.833
        let longitudeHour = coordinate.longitude / 15.0
        let N = Double(dayOfYear)
        let base = (event == .sunrise ? 6.0 : 18.0)
        let t = N + ((base - longitudeHour) / 24.0)
        let M = (0.9856 * t) - 3.289
        var L = M + (1.916 * sinDeg(M)) + (0.02 * sinDeg(2 * M)) + 282.634
        L = normalizeDegrees(L)
        var RA = atan(0.91764 * tanDeg(L)) * 180 / .pi
        RA = normalizeDegrees(RA)
        let Lquadrant = floor(L / 90.0) * 90.0
        let RAquadrant = floor(RA / 90.0) * 90.0
        RA = RA + (Lquadrant - RAquadrant)
        RA /= 15.0
        
        let sinDec = 0.39782 * sinDeg(L)
        let cosDec = cos(asin(sinDec))
        let cosH = (cosDeg(zenith) - (sinDec * sinDeg(coordinate.latitude))) / (cosDec * cosDeg(coordinate.latitude))
        if cosH > 1 || cosH < -1 {
            return nil
        }
        
        var H = event == .sunrise ? 360.0 - acosDeg(cosH) : acosDeg(cosH)
        H /= 15.0
        let T = H + RA - (0.06571 * t) - 6.622
        var UT = T - longitudeHour
        UT = normalizeHours(UT)
        
        // UT is in UTC time - convert to hours, minutes, seconds
        let utcHour = Int(UT)
        let minute = Int((UT - Double(utcHour)) * 60.0)
        let second = Int((((UT - Double(utcHour)) * 60.0) - Double(minute)) * 60.0)
        
        // Convert UTC time to local time by adding timezone offset
        let localOffsetSeconds = timeZone.secondsFromGMT(for: date)
        let localOffsetHours = Double(localOffsetSeconds) / 3600.0
        
        // Add offset to convert UTC to local time
        var localHours = Double(utcHour) + localOffsetHours
        
        // Handle day overflow
        var dayOffset = 0
        if localHours < 0 {
            localHours += 24
            dayOffset = -1
        } else if localHours >= 24 {
            localHours -= 24
            dayOffset = 1
        }
        
        let hour = Int(localHours)
        
        // Get year/month/day from the input date and apply day offset
        var adjustedDate = date
        if dayOffset != 0 {
            adjustedDate = calendar.date(byAdding: .day, value: dayOffset, to: date) ?? date
        }
        
        var components = calendar.dateComponents([.year, .month, .day], from: adjustedDate)
        components.hour = hour
        components.minute = minute
        components.second = second
        components.nanosecond = 0
        
        return calendar.date(from: components)
    }
    
    private static func sinDeg(_ degrees: Double) -> Double {
        sin(degrees * .pi / 180.0)
    }
    
    private static func cosDeg(_ degrees: Double) -> Double {
        cos(degrees * .pi / 180.0)
    }
    
    private static func tanDeg(_ degrees: Double) -> Double {
        tan(degrees * .pi / 180.0)
    }
    
    private static func acosDeg(_ value: Double) -> Double {
        acos(value) * 180.0 / .pi
    }
    
    private static func normalizeDegrees(_ value: Double) -> Double {
        var angle = value.truncatingRemainder(dividingBy: 360.0)
        if angle < 0 { angle += 360.0 }
        return angle
    }
    
    private static func normalizeHours(_ value: Double) -> Double {
        var hourValue = value.truncatingRemainder(dividingBy: 24.0)
        if hourValue < 0 { hourValue += 24.0 }
        return hourValue
    }
}

private struct SolarCacheKey: Hashable {
    let event: SolarEvent
    let coordinate: CLLocationCoordinate2D
    let date: Date
    let offsetMinutes: SolarTrigger.EventOffset
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(event)
        hasher.combine(Int(coordinate.latitude * 1000))
        hasher.combine(Int(coordinate.longitude * 1000))
        hasher.combine(date.timeIntervalSince1970)
        switch offsetMinutes {
        case .minutes(let value):
            hasher.combine(value)
        }
    }
    
    static func == (lhs: SolarCacheKey, rhs: SolarCacheKey) -> Bool {
        lhs.event == rhs.event &&
        abs(lhs.coordinate.latitude - rhs.coordinate.latitude) < 0.0005 &&
        abs(lhs.coordinate.longitude - rhs.coordinate.longitude) < 0.0005 &&
        lhs.date == rhs.date &&
        lhs.offsetMinutes == rhs.offsetMinutes
    }
}
