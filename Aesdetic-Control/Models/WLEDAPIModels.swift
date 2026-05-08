//  WLEDAPIModels.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import Foundation
import SwiftUI

// MARK: - API Request Models

/// Model for updating WLED device state via API
/// - Note: Transition time is expressed in deciseconds (tenths of a second) per WLED JSON API.
struct WLEDStateUpdate: Codable {
    /// Power state (on/off)
    let on: Bool?
    /// Brightness (0-255)
    let bri: Int?
    /// Array of segment updates
    let seg: [SegmentUpdate]?
    let udpn: UDPNUpdate?
    /// One-off transition time for this update (deciseconds, encoded as `tt`)
    private let transitionDeciseconds: Int?
    /// Default transition time for subsequent updates (deciseconds, encoded as `transition`)
    private let defaultTransitionDeciseconds: Int?
    /// Main segment index
    private let mainSegment: Int?
    /// Apply preset by ID
    let ps: Int?
    /// Current playlist ID (settable in WLED JSON API)
    let pl: Int?
    /// Night Light configuration
    let nl: NightLightUpdate?
    /// Live override release (0 disables realtime streaming)
    let lor: Int?
    /// Reboot device
    let rb: Bool?
    
    init(
        on: Bool? = nil,
        bri: Int? = nil,
        seg: [SegmentUpdate]? = nil,
        udpn: UDPNUpdate? = nil,
        transitionDeciseconds: Int? = nil,
        defaultTransitionDeciseconds: Int? = nil,
        mainSegment: Int? = nil,
        ps: Int? = nil,
        pl: Int? = nil,
        nl: NightLightUpdate? = nil,
        lor: Int? = nil,
        rb: Bool? = nil
    ) {
        self.on = on
        self.bri = bri
        self.seg = seg
        self.udpn = udpn
        self.transitionDeciseconds = transitionDeciseconds
        self.defaultTransitionDeciseconds = defaultTransitionDeciseconds
        self.mainSegment = mainSegment
        self.ps = ps
        self.pl = pl
        self.nl = nl
        self.lor = lor
        self.rb = rb
    }
    
    /// Convenience accessor for one-off transition time (deciseconds)
    var transition: Int? {
        transitionDeciseconds
    }
    
    enum CodingKeys: String, CodingKey {
        case on, bri, seg, udpn
        case transitionDeciseconds = "tt"  // WLED expects "tt" field name
        case defaultTransitionDeciseconds = "transition"
        case mainSegment = "mainseg"
        case ps, pl, nl, lor, rb
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(on, forKey: .on)
        try container.encodeIfPresent(bri, forKey: .bri)
        try container.encodeIfPresent(seg, forKey: .seg)
        try container.encodeIfPresent(udpn, forKey: .udpn)
        if let transitionDeciseconds {
            try container.encode(transitionDeciseconds, forKey: .transitionDeciseconds)
        }
        if let defaultTransitionDeciseconds {
            try container.encode(defaultTransitionDeciseconds, forKey: .defaultTransitionDeciseconds)
        }
        if let mainSegment {
            try container.encode(mainSegment, forKey: .mainSegment)
        }
        try container.encodeIfPresent(ps, forKey: .ps)
        try container.encodeIfPresent(pl, forKey: .pl)
        try container.encodeIfPresent(nl, forKey: .nl)
        try container.encodeIfPresent(lor, forKey: .lor)
        try container.encodeIfPresent(rb, forKey: .rb)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.on = try container.decodeIfPresent(Bool.self, forKey: .on)
        self.bri = try container.decodeIfPresent(Int.self, forKey: .bri)
        self.seg = try container.decodeIfPresent([SegmentUpdate].self, forKey: .seg)
        self.udpn = try container.decodeIfPresent(UDPNUpdate.self, forKey: .udpn)
        self.transitionDeciseconds = try container.decodeIfPresent(Int.self, forKey: .transitionDeciseconds)
        self.defaultTransitionDeciseconds = try container.decodeIfPresent(Int.self, forKey: .defaultTransitionDeciseconds)
        self.mainSegment = try container.decodeIfPresent(Int.self, forKey: .mainSegment)
        self.ps = try container.decodeIfPresent(Int.self, forKey: .ps)
        self.pl = try container.decodeIfPresent(Int.self, forKey: .pl)
        self.nl = try container.decodeIfPresent(NightLightUpdate.self, forKey: .nl)
        self.lor = try container.decodeIfPresent(Int.self, forKey: .lor)
        self.rb = try container.decodeIfPresent(Bool.self, forKey: .rb)
    }
}

// UDP sync options
struct UDPNUpdate: Codable {
    let send: Bool?
    let recv: Bool?
    let nn: Int?
}

// Night Light update
struct NightLightUpdate: Codable {
    let on: Bool?
    let dur: Int?
    let mode: Int?
    let tbri: Int?
}

/// Model for updating specific WLED segments
struct SegmentUpdate: Codable {
    // Identification
    let id: Int?

    // Bounds and options
    let start: Int?
    let stop: Int?
    let len: Int?
    let grp: Int?
    let spc: Int?
    let ofs: Int?

    // State
    let on: Bool?
    let bri: Int?
    let col: [[Int]]?
    /// Color temperature (0-255, 0=warm, 255=cool)
    let cct: Int?

    // Effect
    let fx: Int?
    let sx: Int?
    let ix: Int?
    let pal: Int?
    let c1: Int?
    let c2: Int?
    let c3: Int?

    // Flags
    let sel: Bool?
    let rev: Bool?
    let mi: Bool?
    let cln: Int?
    let o1: Bool?
    let o2: Bool?
    let o3: Bool?
    let si: Int?
    let m12: Int?
    let setId: Int?
    let name: String?
    /// Freeze flag: true = freeze segment (stop animations), false = resume
    let frz: Bool?

    init(
        id: Int? = nil,
        start: Int? = nil,
        stop: Int? = nil,
        len: Int? = nil,
        grp: Int? = nil,
        spc: Int? = nil,
        ofs: Int? = nil,
        on: Bool? = nil,
        bri: Int? = nil,
        col: [[Int]]? = nil,
        cct: Int? = nil,
        fx: Int? = nil,
        sx: Int? = nil,
        ix: Int? = nil,
        pal: Int? = nil,
        c1: Int? = nil,
        c2: Int? = nil,
        c3: Int? = nil,
        sel: Bool? = nil,
        rev: Bool? = nil,
        mi: Bool? = nil,
        cln: Int? = nil,
        o1: Bool? = nil,
        o2: Bool? = nil,
        o3: Bool? = nil,
        si: Int? = nil,
        m12: Int? = nil,
        setId: Int? = nil,
        name: String? = nil,
        frz: Bool? = nil
    ) {
        self.id = id
        self.start = start
        self.stop = stop
        self.len = len
        self.grp = grp
        self.spc = spc
        self.ofs = ofs
        self.on = on
        self.bri = bri
        self.col = col
        self.cct = cct
        self.fx = fx
        self.sx = sx
        self.ix = ix
        self.pal = pal
        self.c1 = c1
        self.c2 = c2
        self.c3 = c3
        self.sel = sel
        self.rev = rev
        self.mi = mi
        self.cln = cln
        self.o1 = o1
        self.o2 = o2
        self.o3 = o3
        self.si = si
        self.m12 = m12
        self.setId = setId
        self.name = name
        self.frz = frz
    }
    
    // CRITICAL: Custom encoding to omit col when nil
    // Omit col when intentionally sending CCT-only updates
    enum CodingKeys: String, CodingKey {
        case id, start, stop, len, grp, spc
        case ofs = "of"
        case on, bri, col, cct
        case fx, sx, ix, pal
        case c1, c2, c3
        case sel, rev, mi, cln
        case o1, o2, o3, si, m12
        case setId = "set"
        case name = "n"
        case frz
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Only encode col if it's not nil
        // This ensures CCT-only updates don't include col: null
        if let col = col {
            try container.encode(col, forKey: .col)
        }
        // Explicitly don't encode col if nil - this omits it from JSON
        
        // Encode all other fields if they're not nil
        try id.map { try container.encode($0, forKey: .id) }
        try start.map { try container.encode($0, forKey: .start) }
        try stop.map { try container.encode($0, forKey: .stop) }
        try len.map { try container.encode($0, forKey: .len) }
        try grp.map { try container.encode($0, forKey: .grp) }
        try spc.map { try container.encode($0, forKey: .spc) }
        try ofs.map { try container.encode($0, forKey: .ofs) }
        try on.map { try container.encode($0, forKey: .on) }
        try bri.map { try container.encode($0, forKey: .bri) }
        try cct.map { try container.encode($0, forKey: .cct) }
        try fx.map { try container.encode($0, forKey: .fx) }
        try sx.map { try container.encode($0, forKey: .sx) }
        try ix.map { try container.encode($0, forKey: .ix) }
        try pal.map { try container.encode($0, forKey: .pal) }
        try c1.map { try container.encode($0, forKey: .c1) }
        try c2.map { try container.encode($0, forKey: .c2) }
        try c3.map { try container.encode($0, forKey: .c3) }
        try sel.map { try container.encode($0, forKey: .sel) }
        try rev.map { try container.encode($0, forKey: .rev) }
        try mi.map { try container.encode($0, forKey: .mi) }
        try cln.map { try container.encode($0, forKey: .cln) }
        try o1.map { try container.encode($0, forKey: .o1) }
        try o2.map { try container.encode($0, forKey: .o2) }
        try o3.map { try container.encode($0, forKey: .o3) }
        try si.map { try container.encode($0, forKey: .si) }
        try m12.map { try container.encode($0, forKey: .m12) }
        try setId.map { try container.encode($0, forKey: .setId) }
        try name.map { try container.encode($0, forKey: .name) }
        try frz.map { try container.encode($0, forKey: .frz) }
    }
}

// MARK: - API Response Models (Extended)

/// Extended WLED response with additional API metadata
struct WLEDAPIResponse: Codable {
    let success: Bool
    let data: WLEDResponse?
    let error: String?
    
    init(success: Bool, data: WLEDResponse? = nil, error: String? = nil) {
        self.success = success
        self.data = data
        self.error = error
    }
}

struct WLEDSuccessResponse: Codable {
    let success: Bool
}

// MARK: - Future API Models (Prepared for extension)

/// Model for WLED effects management (future use)
struct WLEDEffect: Codable, Identifiable {
    let id: Int
    let name: String
    let description: String?
}

/// Model for WLED presets management (future use)
struct WLEDPreset: Codable, Identifiable {
    let id: Int
    let name: String
    let quickLoad: String?
    let segment: SegmentUpdate?
    let state: WLEDStateUpdate?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case quickLoad = "ql"
        case segment = "seg"
        case state = "win"
    }
}

struct WLEDPresetSaveRequest {
    let id: Int
    let name: String
    let quickLoad: String?
    let state: WLEDStateUpdate?
    let saveOnly: Bool?
    let includeBrightness: Bool?
    let saveSegmentBounds: Bool?
    let selectedSegmentsOnly: Bool?
    let transitionDeciseconds: Int?
    let applyAtBoot: Bool?
    let customAPICommand: String?

    init(
        id: Int,
        name: String,
        quickLoad: String?,
        state: WLEDStateUpdate?,
        saveOnly: Bool? = nil,
        includeBrightness: Bool? = nil,
        saveSegmentBounds: Bool? = nil,
        selectedSegmentsOnly: Bool? = nil,
        transitionDeciseconds: Int? = nil,
        applyAtBoot: Bool? = nil,
        customAPICommand: String? = nil
    ) {
        self.id = id
        self.name = name
        self.quickLoad = quickLoad
        self.state = state
        self.saveOnly = saveOnly
        self.includeBrightness = includeBrightness
        self.saveSegmentBounds = saveSegmentBounds
        self.selectedSegmentsOnly = selectedSegmentsOnly
        self.transitionDeciseconds = transitionDeciseconds
        self.applyAtBoot = applyAtBoot
        self.customAPICommand = customAPICommand
    }
}

/// Model for WLED playlist management
struct WLEDPlaylist: Codable, Identifiable {
    let id: Int
    let name: String
    let presets: [Int]
    let duration: [Int]  // Per-step entry duration in deciseconds (native WLED `dur`)
    let transition: [Int]  // Per-step transition in deciseconds (native WLED)
    let `repeat`: Int?
    let endPresetId: Int?
    let shuffle: Int?
}

/// Model for WLED timer/macro configuration
/// WLED timers are stored in /json/cfg under "timers.ins"
/// Each timer slot triggers a preset ID (WLED "macro") based on time
struct WLEDTimer: Codable, Identifiable {
    /// Timer slot ID (0-based index, typically 0-9)
    let id: Int
    /// Enable/disable timer
    let enabled: Bool
    /// Hour (0-23, 24 = hourly, 255 = sunrise, 254 = sunset)
    let hour: Int
    /// Minute (0-59 for standard timers, offset for sunrise/sunset)
    let minute: Int
    /// Days of week bitmask (WLED native: bit 0=Mon ... bit 6=Sun)
    /// 0x01 = Monday, 0x02 = Tuesday, ..., 0x40 = Sunday
    /// 0x7F = All days, 0x1F = Weekdays only (Mon-Fri)
    let days: Int
    /// Preset ID to trigger (WLED "macro" field)
    let macroId: Int
    /// Optional start date month (1-12)
    let startMonth: Int?
    /// Optional start date day (1-31)
    let startDay: Int?
    /// Optional end date month (1-12)
    let endMonth: Int?
    /// Optional end date day (1-31)
    let endDay: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case enabled = "en"
        case hour = "hour"
        case minute = "min"
        case days = "dow"
        case macroId = "macro"
        case startMonth = "startMonth"
        case startDay = "startDay"
        case endMonth = "endMonth"
        case endDay = "endDay"
    }
}

/// Model for updating WLED timer configuration
struct WLEDTimerUpdate: Codable {
    /// Timer slot ID
    let id: Int
    /// Enable/disable timer
    let enabled: Bool?
    /// Hour (0-23, 24 = hourly, 255 = sunrise, 254 = sunset)
    let hour: Int?
    /// Minute (0-59 for standard timers, offset for sunrise/sunset)
    let minute: Int?
    /// Days of week bitmask (WLED native: bit 0=Mon ... bit 6=Sun)
    let days: Int?
    /// Preset ID to trigger (WLED "macro" field)
    let macroId: Int?
    /// Optional start date month (1-12)
    let startMonth: Int?
    /// Optional start date day (1-31)
    let startDay: Int?
    /// Optional end date month (1-12)
    let endMonth: Int?
    /// Optional end date day (1-31)
    let endDay: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case enabled = "en"
        case hour = "hour"
        case minute = "min"
        case days = "dow"
        case macroId = "macro"
        case startMonth = "startMonth"
        case startDay = "startDay"
        case endMonth = "endMonth"
        case endDay = "endDay"
    }
}

/// WLED macro trigger bindings in /json/cfg.
/// These are native firmware hooks that can execute a preset/playlist macro ID.
struct WLEDMacroBindings: Equatable {
    let buttonPressMacro: Int
    let buttonLongPressMacro: Int
    let buttonDoublePressMacro: Int
    let alexaOnMacro: Int
    let alexaOffMacro: Int
    let nightLightMacro: Int
}

/// Partial update payload for WLED macro trigger bindings.
struct WLEDMacroBindingsUpdate {
    let buttonPressMacro: Int?
    let buttonLongPressMacro: Int?
    let buttonDoublePressMacro: Int?
    let alexaOnMacro: Int?
    let alexaOffMacro: Int?
    let nightLightMacro: Int?
}

/// Native WLED Alexa integration settings stored in /json/cfg.
struct WLEDAlexaIntegrationSettings: Equatable {
    var isEnabled: Bool
    var invocationName: String
    var exposedPresetCount: Int
}

/// Native WLED integration settings stored in /json/cfg under the "if" tree.
struct WLEDNativeIntegrationSettings: Equatable {
    var sync: WLEDIntegrationSyncSettings
    var realtime: WLEDIntegrationRealtimeSettings
    var mqtt: WLEDIntegrationMQTTSettings
    var hue: WLEDIntegrationHueSettings

    static let defaults = WLEDNativeIntegrationSettings(
        sync: .defaults,
        realtime: .defaults,
        mqtt: .defaults,
        hue: .defaults
    )
}

struct WLEDIntegrationSyncSettings: Equatable {
    var udpPort: Int
    var secondaryUdpPort: Int
    var espNowEnabled: Bool
    var sendGroups: Int
    var receiveGroups: Int
    var receiveBrightness: Bool
    var receiveColor: Bool
    var receiveEffects: Bool
    var receivePalette: Bool
    var receiveSegmentOptions: Bool
    var receiveSegmentBounds: Bool
    var sendOnStart: Bool
    var sendDirectChanges: Bool
    var sendButtonChanges: Bool
    var sendAlexaChanges: Bool
    var sendHueChanges: Bool
    var udpRetransmissions: Int
    var nodeListEnabled: Bool
    var nodeBroadcastEnabled: Bool

    static let defaults = WLEDIntegrationSyncSettings(
        udpPort: 21324,
        secondaryUdpPort: 65506,
        espNowEnabled: false,
        sendGroups: 1,
        receiveGroups: 1,
        receiveBrightness: true,
        receiveColor: true,
        receiveEffects: true,
        receivePalette: true,
        receiveSegmentOptions: false,
        receiveSegmentBounds: false,
        sendOnStart: false,
        sendDirectChanges: true,
        sendButtonChanges: false,
        sendAlexaChanges: false,
        sendHueChanges: false,
        udpRetransmissions: 0,
        nodeListEnabled: true,
        nodeBroadcastEnabled: true
    )
}

enum WLEDRealtimeProtocolMode: Int, CaseIterable, Identifiable, Equatable {
    case e131 = 5568
    case artNet = 6454
    case custom = 0

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .e131:
            return "E1.31 (sACN)"
        case .artNet:
            return "Art-Net"
        case .custom:
            return "Custom Port"
        }
    }

    static func mode(for port: Int) -> WLEDRealtimeProtocolMode {
        switch port {
        case WLEDRealtimeProtocolMode.e131.rawValue:
            return .e131
        case WLEDRealtimeProtocolMode.artNet.rawValue:
            return .artNet
        default:
            return .custom
        }
    }
}

enum WLEDDMXMode: Int, CaseIterable, Identifiable, Equatable {
    case disabled = 0
    case singleRGB = 1
    case singleDRGB = 2
    case effect = 3
    case multiRGB = 4
    case dimmerMultiRGB = 5
    case multiRGBW = 6
    case effectWhite = 7
    case effectSegment = 8
    case effectSegmentWhite = 9
    case preset = 10

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .disabled:
            return "Disabled"
        case .singleRGB:
            return "Single RGB"
        case .singleDRGB:
            return "Single DRGB"
        case .effect:
            return "Effect"
        case .multiRGB:
            return "Multi RGB"
        case .dimmerMultiRGB:
            return "Dimmer + Multi RGB"
        case .multiRGBW:
            return "Multi RGBW"
        case .effectWhite:
            return "Effect + White"
        case .effectSegment:
            return "Effect Segment"
        case .effectSegmentWhite:
            return "Effect Segment + White"
        case .preset:
            return "Preset"
        }
    }
}

struct WLEDIntegrationRealtimeSettings: Equatable {
    var receiveRealtime: Bool
    var mainSegmentOnly: Bool
    var respectLedMaps: Bool
    var protocolMode: WLEDRealtimeProtocolMode
    var port: Int
    var multicast: Bool
    var startUniverse: Int
    var skipOutOfSequence: Bool
    var dmxStartAddress: Int
    var dmxSegmentSpacing: Int
    var e131Priority: Int
    var dmxMode: WLEDDMXMode
    var timeoutMs: Int
    var forceMaxBrightness: Bool
    var disableGammaCorrection: Bool
    var ledOffset: Int

    static let defaults = WLEDIntegrationRealtimeSettings(
        receiveRealtime: false,
        mainSegmentOnly: false,
        respectLedMaps: false,
        protocolMode: .e131,
        port: 5568,
        multicast: false,
        startUniverse: 1,
        skipOutOfSequence: false,
        dmxStartAddress: 1,
        dmxSegmentSpacing: 0,
        e131Priority: 0,
        dmxMode: .disabled,
        timeoutMs: 2500,
        forceMaxBrightness: false,
        disableGammaCorrection: false,
        ledOffset: 0
    )
}

struct WLEDIntegrationMQTTSettings: Equatable {
    var enabled: Bool
    var broker: String
    var port: Int
    var username: String
    var password: String
    var clientID: String
    var deviceTopic: String
    var groupTopic: String
    var publishButtonPresses: Bool
    var retainMessages: Bool

    static let defaults = WLEDIntegrationMQTTSettings(
        enabled: false,
        broker: "",
        port: 1883,
        username: "",
        password: "",
        clientID: "",
        deviceTopic: "wled",
        groupTopic: "",
        publishButtonPresses: false,
        retainMessages: false
    )
}

struct WLEDIntegrationHueSettings: Equatable {
    var enabled: Bool
    var lightID: Int
    var pollIntervalMs: Int
    var receiveOnOff: Bool
    var receiveBrightness: Bool
    var receiveColor: Bool
    var bridgeIP: String

    static let defaults = WLEDIntegrationHueSettings(
        enabled: false,
        lightID: 1,
        pollIntervalMs: 2500,
        receiveOnOff: true,
        receiveBrightness: true,
        receiveColor: true,
        bridgeIP: "0.0.0.0"
    )
}

// MARK: - WLED Transition Constants

/// Maximum WLED transition time in deciseconds (tenths of a second)
/// WLED's `tt` field accepts values from 0 to 65535 deciseconds
let maxWLEDTransitionDeciseconds = 65535

/// Maximum WLED transition time in seconds (~109.2 minutes)
/// Calculated from maxWLEDTransitionDeciseconds: 65535 / 10 = 6553.5 seconds
let maxWLEDTransitionSeconds = 6553.5

/// Practical upper bound for native transitions in this app (policy cap below WLED max)
let maxWLEDNativeTransitionSeconds = maxWLEDTransitionSeconds

/// Playlist constraints: WLED uses per-step decisecond timing and 100-entry playlists.
let maxWLEDPlaylistEntries = 100
let maxWLEDPlaylistTransitionSeconds = 65.0
let maxWLEDPlaylistTransitionDeciseconds = 650
let maxWLEDPlaylistTransitionMilliseconds = maxWLEDPlaylistTransitionDeciseconds * 100
let maxWLEDPlaylistDurationSeconds = 3600.0
let maxWLEDPresetSlots = 250
let alexaReservedPresetRange = 1...9
let appManagedPresetLowerBound = alexaReservedPresetRange.upperBound + 1
let appManagedPresetRange = appManagedPresetLowerBound...maxWLEDPresetSlots
let presetSlotReserve = 20
// Legacy quarantine for old preset-store-backed live transitions. New live
// transitions use WLED native `tt` / state updates and never allocate here.
let temporaryTransitionReservedPresetLower = 170
let temporaryTransitionReservedPresetUpper = 250
let temporaryTransitionCleanupGraceMinutes = 15.0

enum TransitionGenerationContext: String, Codable {
    case persistentAutomation
}

enum GeneratedPlaylistTimingMode: Equatable {
    case fullBlend
    case boundaryCompensated(padDeciseconds: Int)

    var padDeciseconds: Int {
        switch self {
        case .fullBlend:
            return 0
        case .boundaryCompensated(let padDeciseconds):
            return max(0, padDeciseconds)
        }
    }

    var label: String {
        switch self {
        case .fullBlend:
            return "full-blend"
        case .boundaryCompensated(let padDeciseconds):
            return "boundary-compensated(\(max(0, padDeciseconds))ds)"
        }
    }
}

enum TransitionStepQualityLabel: String, Codable {
    case high
    case balanced
    case conservative

    var displayName: String {
        switch self {
        case .high: return "High"
        case .balanced: return "Balanced"
        case .conservative: return "Conservative"
        }
    }
}

struct TransitionStepProfile: Equatable {
    let context: TransitionGenerationContext
    let baseLegSeconds: Double
    let legSeconds: Double
    let qualityLabel: TransitionStepQualityLabel
    let steps: Int
    let slotsRequired: Int
    let fitsBudget: Bool
    let wasCoarsened: Bool
    let availableSlots: Int?
    let perAutomationBudget: Int?
    let reserve: Int?
    let maxDurationSecondsAtCurrentQuality: Double?
}

enum TransitionDurationPicker {
    static let maxMinutes = 60
    static let maxSeconds = maxMinutes * 60
    static let recommendedMaxMinutes = 35
    static let recommendedMaxSeconds = recommendedMaxMinutes * 60
    static let recommendedMaxRatio = Double(recommendedMaxSeconds) / Double(maxSeconds)

    static func clampedTotalSeconds(_ seconds: Double) -> Int {
        max(0, min(Int(seconds.rounded()), maxSeconds))
    }

    static func components(from seconds: Double) -> (minutes: Int, seconds: Int) {
        let total = clampedTotalSeconds(seconds)
        return (total / 60, total % 60)
    }

    static func totalSeconds(minutes: Int, seconds: Int) -> Int {
        let clampedMinutes = max(0, min(minutes, maxMinutes))
        if clampedMinutes == maxMinutes {
            return maxSeconds
        }
        let clampedSeconds = max(0, min(seconds, 59))
        return clampedMinutes * 60 + clampedSeconds
    }

    static func clockString(seconds: Double) -> String {
        let comps = components(from: seconds)
        return "\(comps.minutes):\(String(format: "%02d", comps.seconds))"
    }

    static func summaryString(seconds: Double) -> String {
        let total = clampedTotalSeconds(seconds)
        if total == 0 {
            return "Instant"
        }
        return clockString(seconds: Double(total))
    }

    static func exceedsRecommendedMax(_ seconds: Double) -> Bool {
        clampedTotalSeconds(seconds) > recommendedMaxSeconds
    }
}

// MARK: - API Configuration Models

/// Configuration for WLED API client
struct WLEDAPIConfiguration {
    let timeoutInterval: TimeInterval
    let maxRetries: Int
    let retryDelay: TimeInterval
    let enableLogging: Bool
    
    static let `default` = WLEDAPIConfiguration(
        timeoutInterval: 10.0,
        maxRetries: 3,
        retryDelay: 1.0,
        enableLogging: true
    )
}

// MARK: - Color Conversion Extensions

extension Color {    
    /// Convert Color to RGBW array for WLED API (with white channel)
    func toRGBWArray() -> [Int] {
        let rgb = toRGBArray()
        let white = min(rgb[0], rgb[1], rgb[2]) // Simple white extraction
        return [rgb[0], rgb[1], rgb[2], white]
    }
    
    /// Create Color from RGB array received from WLED API
    static func fromRGBArray(_ rgb: [Int]) -> Color {
        guard rgb.count >= 3 else { return .black }
        
        let red = Double(max(0, min(255, rgb[0]))) / 255.0
        let green = Double(max(0, min(255, rgb[1]))) / 255.0
        let blue = Double(max(0, min(255, rgb[2]))) / 255.0
        
        return Color(red: red, green: green, blue: blue)
    }
    static func lerp(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let ar = a.toRGBArray()
        let br = b.toRGBArray()
        func mix(_ x: Int, _ y: Int) -> Double { Double(x) * (1 - t) + Double(y) * t }
        return Color(
            red: mix(ar[0], br[0]) / 255.0,
            green: mix(ar[1], br[1]) / 255.0,
            blue: mix(ar[2], br[2]) / 255.0
        )
    }
}

// MARK: - WebSocket Models

/// WLED device info from WebSocket response
struct WLEDInfo: Codable {
    let name: String
    let mac: String
    let version: String
    let brand: String?
    let product: String?
    let uptime: Int?
    
    enum CodingKeys: String, CodingKey {
        case name, mac
        case version = "ver"
        case brand, product
        case uptime = "uptime"
    }
}

/// Device state update model for real-time synchronization
struct WLEDDeviceStateUpdate {
    let deviceId: String
    let state: WLEDState?
    let info: WLEDInfo?
    let timestamp: Date
    
    init(deviceId: String, state: WLEDState? = nil, info: WLEDInfo? = nil, timestamp: Date = Date()) {
        self.deviceId = deviceId
        self.state = state
        self.info = info
        self.timestamp = timestamp
    }
}

// MARK: - Configuration Models

/// Model for updating WLED device configuration
/// Used to change device name (server description) and other settings
struct WLEDConfigUpdate: Codable {
    /// Device/Server description (the name shown in UI)
    let name: String?
    
    init(name: String? = nil) {
        self.name = name
    }
    
    enum CodingKeys: String, CodingKey {
        case name = "server-name"
    }
}

// MARK: - LED Configuration Models

/// LED hardware configuration for WLED devices
struct LEDConfiguration: Codable {
    /// LED strip type (WS281x, SK6812, etc.)
    let stripType: Int
    /// Color order (GRB, RGB, BRG, etc.)
    let colorOrder: Int
    /// GPIO pin for data
    let gpioPin: Int
    /// Number of LEDs
    let ledCount: Int
    /// Start LED index
    let startLED: Int
    /// Skip first N LEDs
    let skipFirstLEDs: Int
    /// Reverse direction
    let reverseDirection: Bool
    /// Refresh when off
    let offRefresh: Bool
    /// Auto white mode (0=none, 1=brighter, 2=accurate, 3=dual, 4=max)
    let autoWhiteMode: Int
    /// Global auto white override (255 = use each output's own setting)
    let globalAutoWhiteMode: Int
    /// White channel swap packed into high bits of WLED bus color order
    let whiteChannelSwap: Int
    /// Bus clock/PWM frequency from hw.led.ins[n].freq
    let signalFrequency: Int
    /// Bus driver preference (0=RMT/default, 1=I2S)
    let driverType: Int
    /// Optional CCT Kelvin range from config (min/max)
    let cctKelvinMin: Int?
    let cctKelvinMax: Int?
    /// Maximum current per LED in mA
    let maxCurrentPerLED: Int
    /// Maximum total current in mA
    let maxTotalCurrent: Int
    /// Use per-output limiter
    let usePerOutputLimiter: Bool
    /// Enable automatic brightness limiter
    let enableABL: Bool
    /// WLED "White Balance correction" setting (hw.led.cct)
    let whiteBalanceCorrection: Bool
    /// WLED "Calculate CCT from RGB" setting (hw.led.cr)
    let calculateCCTFromRGB: Bool
    /// WLED "CCT IC used" setting (hw.led.ic)
    let cctICUsed: Bool
    /// WLED CCT blending percentage, -100...100 (hw.led.cb)
    let cctBlending: Int
    /// WLED global brightness factor, 1...255 (light.scale-bri)
    let globalBrightnessFactor: Int
    /// WLED target refresh rate, 0...250 FPS (hw.led.fps)
    let targetFPS: Int
    /// WLED palette wrapping/blend mode (light.pal-mode)
    let paletteBlendMode: Int
    /// WLED make-a-segment-for-each-output setting (light.aseg)
    let autoSegments: Bool
    /// WLED gamma correction for color (light.gc.col != 1)
    let gammaCorrectColor: Bool
    /// WLED gamma correction for brightness (light.gc.bri != 1)
    let gammaCorrectBrightness: Bool
    /// WLED gamma value (light.gc.val)
    let gammaValue: Double

    init(
        stripType: Int,
        colorOrder: Int,
        gpioPin: Int,
        ledCount: Int,
        startLED: Int,
        skipFirstLEDs: Int,
        reverseDirection: Bool,
        offRefresh: Bool,
        autoWhiteMode: Int,
        globalAutoWhiteMode: Int = 255,
        whiteChannelSwap: Int = 0,
        signalFrequency: Int = 0,
        driverType: Int = 0,
        cctKelvinMin: Int? = nil,
        cctKelvinMax: Int? = nil,
        maxCurrentPerLED: Int,
        maxTotalCurrent: Int,
        usePerOutputLimiter: Bool,
        enableABL: Bool,
        whiteBalanceCorrection: Bool = false,
        calculateCCTFromRGB: Bool = false,
        cctICUsed: Bool = false,
        cctBlending: Int = 0,
        globalBrightnessFactor: Int = 100,
        targetFPS: Int = 42,
        paletteBlendMode: Int = 0,
        autoSegments: Bool = false,
        gammaCorrectColor: Bool = true,
        gammaCorrectBrightness: Bool = false,
        gammaValue: Double = 2.2
    ) {
        self.stripType = stripType
        self.colorOrder = colorOrder
        self.gpioPin = gpioPin
        self.ledCount = ledCount
        self.startLED = startLED
        self.skipFirstLEDs = skipFirstLEDs
        self.reverseDirection = reverseDirection
        self.offRefresh = offRefresh
        self.autoWhiteMode = autoWhiteMode
        self.globalAutoWhiteMode = globalAutoWhiteMode
        self.whiteChannelSwap = whiteChannelSwap
        self.signalFrequency = signalFrequency
        self.driverType = driverType
        self.cctKelvinMin = cctKelvinMin
        self.cctKelvinMax = cctKelvinMax
        self.maxCurrentPerLED = maxCurrentPerLED
        self.maxTotalCurrent = maxTotalCurrent
        self.usePerOutputLimiter = usePerOutputLimiter
        self.enableABL = enableABL
        self.whiteBalanceCorrection = whiteBalanceCorrection
        self.calculateCCTFromRGB = calculateCCTFromRGB
        self.cctICUsed = cctICUsed
        self.cctBlending = cctBlending
        self.globalBrightnessFactor = globalBrightnessFactor
        self.targetFPS = targetFPS
        self.paletteBlendMode = paletteBlendMode
        self.autoSegments = autoSegments
        self.gammaCorrectColor = gammaCorrectColor
        self.gammaCorrectBrightness = gammaCorrectBrightness
        self.gammaValue = gammaValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stripType = try container.decode(Int.self, forKey: .stripType)
        colorOrder = try container.decode(Int.self, forKey: .colorOrder)
        gpioPin = try container.decode(Int.self, forKey: .gpioPin)
        ledCount = try container.decode(Int.self, forKey: .ledCount)
        startLED = try container.decode(Int.self, forKey: .startLED)
        skipFirstLEDs = try container.decode(Int.self, forKey: .skipFirstLEDs)
        reverseDirection = try container.decode(Bool.self, forKey: .reverseDirection)
        offRefresh = try container.decode(Bool.self, forKey: .offRefresh)
        autoWhiteMode = try container.decode(Int.self, forKey: .autoWhiteMode)
        globalAutoWhiteMode = try container.decodeIfPresent(Int.self, forKey: .globalAutoWhiteMode) ?? 255
        whiteChannelSwap = try container.decodeIfPresent(Int.self, forKey: .whiteChannelSwap) ?? 0
        signalFrequency = try container.decodeIfPresent(Int.self, forKey: .signalFrequency) ?? 0
        driverType = try container.decodeIfPresent(Int.self, forKey: .driverType) ?? 0
        maxCurrentPerLED = try container.decode(Int.self, forKey: .maxCurrentPerLED)
        maxTotalCurrent = try container.decode(Int.self, forKey: .maxTotalCurrent)
        usePerOutputLimiter = try container.decode(Bool.self, forKey: .usePerOutputLimiter)
        enableABL = try container.decode(Bool.self, forKey: .enableABL)
        whiteBalanceCorrection = try container.decodeIfPresent(Bool.self, forKey: .whiteBalanceCorrection) ?? false
        calculateCCTFromRGB = try container.decodeIfPresent(Bool.self, forKey: .calculateCCTFromRGB) ?? false
        cctICUsed = try container.decodeIfPresent(Bool.self, forKey: .cctICUsed) ?? false
        cctBlending = try container.decodeIfPresent(Int.self, forKey: .cctBlending) ?? 0
        globalBrightnessFactor = try container.decodeIfPresent(Int.self, forKey: .globalBrightnessFactor) ?? 100
        targetFPS = try container.decodeIfPresent(Int.self, forKey: .targetFPS) ?? 42
        paletteBlendMode = try container.decodeIfPresent(Int.self, forKey: .paletteBlendMode) ?? 0
        autoSegments = try container.decodeIfPresent(Bool.self, forKey: .autoSegments) ?? false
        gammaCorrectColor = try container.decodeIfPresent(Bool.self, forKey: .gammaCorrectColor) ?? true
        gammaCorrectBrightness = try container.decodeIfPresent(Bool.self, forKey: .gammaCorrectBrightness) ?? false
        gammaValue = try container.decodeIfPresent(Double.self, forKey: .gammaValue) ?? 2.2
        cctKelvinMin = nil
        cctKelvinMax = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stripType, forKey: .stripType)
        try container.encode(colorOrder, forKey: .colorOrder)
        try container.encode(gpioPin, forKey: .gpioPin)
        try container.encode(ledCount, forKey: .ledCount)
        try container.encode(startLED, forKey: .startLED)
        try container.encode(skipFirstLEDs, forKey: .skipFirstLEDs)
        try container.encode(reverseDirection, forKey: .reverseDirection)
        try container.encode(offRefresh, forKey: .offRefresh)
        try container.encode(autoWhiteMode, forKey: .autoWhiteMode)
        try container.encode(globalAutoWhiteMode, forKey: .globalAutoWhiteMode)
        try container.encode(whiteChannelSwap, forKey: .whiteChannelSwap)
        try container.encode(signalFrequency, forKey: .signalFrequency)
        try container.encode(driverType, forKey: .driverType)
        try container.encode(maxCurrentPerLED, forKey: .maxCurrentPerLED)
        try container.encode(maxTotalCurrent, forKey: .maxTotalCurrent)
        try container.encode(usePerOutputLimiter, forKey: .usePerOutputLimiter)
        try container.encode(enableABL, forKey: .enableABL)
        try container.encode(whiteBalanceCorrection, forKey: .whiteBalanceCorrection)
        try container.encode(calculateCCTFromRGB, forKey: .calculateCCTFromRGB)
        try container.encode(cctICUsed, forKey: .cctICUsed)
        try container.encode(cctBlending, forKey: .cctBlending)
        try container.encode(globalBrightnessFactor, forKey: .globalBrightnessFactor)
        try container.encode(targetFPS, forKey: .targetFPS)
        try container.encode(paletteBlendMode, forKey: .paletteBlendMode)
        try container.encode(autoSegments, forKey: .autoSegments)
        try container.encode(gammaCorrectColor, forKey: .gammaCorrectColor)
        try container.encode(gammaCorrectBrightness, forKey: .gammaCorrectBrightness)
        try container.encode(gammaValue, forKey: .gammaValue)
    }
    
    enum CodingKeys: String, CodingKey {
        case stripType = "type"
        case colorOrder = "co"
        case gpioPin = "pin"
        case ledCount = "len"
        case startLED = "start"
        case skipFirstLEDs = "skip"
        case reverseDirection = "rev"
        case offRefresh = "rf"
        case autoWhiteMode = "aw"
        case globalAutoWhiteMode = "globalAW"
        case whiteChannelSwap = "wo"
        case signalFrequency = "freq"
        case driverType = "drv"
        case maxCurrentPerLED = "la"
        case maxTotalCurrent = "ma"
        case usePerOutputLimiter = "per"
        case enableABL = "abl"
        case whiteBalanceCorrection = "correctWB"
        case calculateCCTFromRGB = "cctFromRGB"
        case cctICUsed = "cctIC"
        case cctBlending = "cctBlend"
        case globalBrightnessFactor = "brightnessFactor"
        case targetFPS = "fps"
        case paletteBlendMode = "paletteBlend"
        case autoSegments = "autoSegments"
        case gammaCorrectColor = "gammaColor"
        case gammaCorrectBrightness = "gammaBrightness"
        case gammaValue = "gammaValue"
    }
}

struct WLEDSecurityConfiguration: Equatable {
    let otaLocked: Bool
    let wifiSettingsLocked: Bool
    let arduinoOTAEnabled: Bool
    let sameSubnetOnly: Bool
    let otaPasswordConfigured: Bool

    init(
        otaLocked: Bool = true,
        wifiSettingsLocked: Bool = false,
        arduinoOTAEnabled: Bool = false,
        sameSubnetOnly: Bool = true,
        otaPasswordConfigured: Bool = false
    ) {
        self.otaLocked = otaLocked
        self.wifiSettingsLocked = wifiSettingsLocked
        self.arduinoOTAEnabled = arduinoOTAEnabled
        self.sameSubnetOnly = sameSubnetOnly
        self.otaPasswordConfigured = otaPasswordConfigured
    }
}

struct WLEDSecurityConfigurationUpdate: Equatable {
    var otaLocked: Bool
    var wifiSettingsLocked: Bool
    var arduinoOTAEnabled: Bool
    var sameSubnetOnly: Bool
    var otaPassword: String

    init(
        otaLocked: Bool = true,
        wifiSettingsLocked: Bool = false,
        arduinoOTAEnabled: Bool = false,
        sameSubnetOnly: Bool = true,
        otaPassword: String = ""
    ) {
        self.otaLocked = otaLocked
        self.wifiSettingsLocked = wifiSettingsLocked
        self.arduinoOTAEnabled = arduinoOTAEnabled
        self.sameSubnetOnly = sameSubnetOnly
        self.otaPassword = otaPassword
    }

    init(configuration: WLEDSecurityConfiguration) {
        self.init(
            otaLocked: configuration.otaLocked,
            wifiSettingsLocked: configuration.wifiSettingsLocked,
            arduinoOTAEnabled: configuration.arduinoOTAEnabled,
            sameSubnetOnly: configuration.sameSubnetOnly,
            otaPassword: ""
        )
    }

    var isValid: Bool {
        otaPassword.count <= 32
    }
}

/// LED strip types supported by WLED
enum LEDStripType: Int, CaseIterable, Codable {
    case ws281x = 0
    case sk6812 = 1
    case tm1814 = 2
    case ws2801 = 3
    case apa102 = 4
    case lpd8806 = 5
    case tm1829 = 6
    case ucs8903 = 7
    case apa106 = 8
    case tm1914 = 9
    case fw1906 = 10
    case ucs8904 = 11
    case ws2805 = 12
    case sm16825 = 13
    case ws2811White = 14
    case ws281xWWA = 15

    static func fromWLEDType(_ type: Int) -> LEDStripType? {
        switch type {
        case 18, 19:
            return .ws2811White
        case 20, 21:
            return .ws281xWWA
        case 22, 24:
            return .ws281x
        case 25:
            return .tm1829
        case 26:
            return .ucs8903
        case 27:
            return .apa106
        case 28:
            return .fw1906
        case 29:
            return .ucs8904
        case 30:
            return .sk6812
        case 31:
            return .tm1814
        case 32:
            return .ws2805
        case 33:
            return .tm1914
        case 34:
            return .sm16825
        case 41:
            return .ws2811White
        case 42:
            return .ws2805
        case 44:
            return .sk6812
        case 45:
            return .ws2805
        case 46:
            return .sm16825
        case 50:
            return .ws2801
        case 51:
            return .apa102
        case 52, 53, 54:
            return .lpd8806
        case 80:
            return .ws281x
        case 88:
            return .sk6812
        default:
            return LEDStripType(rawValue: type)
        }
    }
    
    var displayName: String {
        switch self {
        case .ws281x: return "WS281x"
        case .sk6812: return "SK6812/WS2814 RGBW"
        case .tm1814: return "TM1814"
        case .ws2801: return "WS2801"
        case .apa102: return "APA102"
        case .lpd8806: return "LPD8806"
        case .tm1829: return "TM1829"
        case .ucs8903: return "UCS8903"
        case .apa106: return "APA106/PL9823"
        case .tm1914: return "TM1914"
        case .fw1906: return "FW1906 GRBCW"
        case .ucs8904: return "UCS8904 RGBW"
        case .ws2805: return "WS2805 RGBCW"
        case .sm16825: return "SM16825 RGBCW"
        case .ws2811White: return "WS2811 White"
        case .ws281xWWA: return "WS281x WWA"
        }
    }
    
    var description: String {
        switch self {
        case .ws281x: return "Standard WS2812/WS2813 RGB LEDs"
        case .sk6812: return "SK6812/WS2814 RGBW LEDs with white channel"
        case .tm1814: return "TM1814 RGB LEDs"
        case .ws2801: return "WS2801 RGB LEDs (3-wire)"
        case .apa102: return "APA102 RGB LEDs (4-wire)"
        case .lpd8806: return "LPD8806 RGB LEDs"
        case .tm1829: return "TM1829 RGB LEDs"
        case .ucs8903: return "UCS8903 RGB LEDs"
        case .apa106: return "APA106/PL9823 RGB LEDs"
        case .tm1914: return "TM1914 RGB LEDs"
        case .fw1906: return "FW1906 GRBCW LEDs"
        case .ucs8904: return "UCS8904 RGBW LEDs"
        case .ws2805: return "WS2805 RGBCW LEDs"
        case .sm16825: return "SM16825 RGBCW LEDs"
        case .ws2811White: return "WS2811 White LEDs"
        case .ws281xWWA: return "WS281x Warm White Amber LEDs"
        }
    }

    var usesWhiteChannel: Bool {
        switch self {
        case .sk6812, .ucs8904, .ws2805, .sm16825, .fw1906, .ws2811White, .ws281xWWA:
            return true
        default:
            return false
        }
    }

    var usesCCT: Bool {
        switch self {
        case .fw1906, .ws2805, .sm16825, .ws281xWWA:
            return true
        default:
            return false
        }
    }
}

/// Color order options for LED strips
enum LEDColorOrder: Int, CaseIterable, Codable {
    case grb = 0
    case rgb = 1
    case brg = 2
    case grbw = 3
    case rgbw = 4
    
    var displayName: String {
        switch self {
        case .grb: return "GRB"
        case .rgb: return "RGB"
        case .brg: return "BRG"
        case .grbw: return "GRBW"
        case .rgbw: return "RGBW"
        }
    }
    
    var description: String {
        switch self {
        case .grb: return "Green-Red-Blue (most common)"
        case .rgb: return "Red-Green-Blue"
        case .brg: return "Blue-Red-Green"
        case .grbw: return "Green-Red-Blue-White"
        case .rgbw: return "Red-Green-Blue-White"
        }
    }

    var usesWhiteChannel: Bool {
        switch self {
        case .grbw, .rgbw:
            return true
        default:
            return false
        }
    }
}

/// Auto white mode options
enum AutoWhiteMode: Int, CaseIterable, Codable {
    case none = 0
    case brighter = 1
    case accurate = 2
    case dual = 3
    case max = 4
    
    var displayName: String {
        switch self {
        case .none: return "None"
        case .brighter: return "Brighter"
        case .accurate: return "Accurate"
        case .dual: return "Dual"
        case .max: return "Max"
        }
    }
    
    var description: String {
        switch self {
        case .none: return "No auto white calculation"
        case .brighter: return "Brighter white calculation"
        case .accurate: return "Accurate white calculation"
        case .dual: return "Dual white calculation"
        case .max: return "Maximum white calculation"
        }
    }
} 
