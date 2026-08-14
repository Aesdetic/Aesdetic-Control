import Foundation
import os.log

enum WLEDSavedNetworkStatus: String, Equatable, Codable {
    case connected
    case saved
    case notTested
}

struct WLEDSavedNetwork: Identifiable, Equatable {
    let slot: Int
    let ssid: String
    let hasPassword: Bool
    let configuredBSSID: String?
    var status: WLEDSavedNetworkStatus

    var id: Int { slot }
}

struct WLEDSavedNetworkSnapshot: Equatable {
    static let stockCapacity = 3

    let networks: [WLEDSavedNetwork]
    let connectedSlot: Int?
    let connectedSSID: String?
    let connectedBSSID: String?
    let signalStrength: Int?
    let firmwareVersion: String?
    let capacity: Int

    var supportsMultipleNetworks: Bool {
        WLEDSafeWiFiChangeService.supportsFallback(firmwareVersion: firmwareVersion)
    }
}

struct WLEDSavedNetworkDraft: Equatable {
    var ssid: String = ""
    var password: String = ""
    var isOpenNetwork: Bool = false

    var normalizedSSID: String {
        ssid.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        guard !normalizedSSID.isEmpty,
              normalizedSSID.lengthOfBytes(using: .utf8) <= 32 else {
            return false
        }
        if isOpenNetwork { return true }
        if password.count == 64 {
            return password.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }
        }
        return (8...63).contains(password.count)
    }

    mutating func clearSensitiveValues() {
        password = ""
    }
}

enum WLEDSavedNetworkMutationPlan: Equatable {
    case update(slot: Int)
    case append(slot: Int)
    case replace(slot: Int)
}

enum WLEDSavedNetworkMutationResult: Equatable {
    case saved(WLEDSavedNetwork)
    case requiresRediscovery
}

enum WLEDSavedNetworkError: LocalizedError, Equatable {
    case unsupportedFirmware
    case invalidCredentials
    case capacityReached
    case replacementRequired
    case connectedNetworkProtected
    case currentNetworkUnknown
    case networkNotFound
    case invalidResponse
    case saveNotConfirmed
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFirmware:
            return "This device needs WLED 0.15 or newer to save more than one Wi-Fi network."
        case .invalidCredentials:
            return "Enter a valid network name and password, or mark the network as open."
        case .capacityReached, .replacementRequired:
            return "This device already has three saved networks. Choose one that is not connected to replace."
        case .connectedNetworkProtected:
            return "The connected network cannot be removed or replaced."
        case .currentNetworkUnknown:
            return "Refresh the connection before replacing or removing a saved network."
        case .networkNotFound:
            return "That saved network could not be found. Refresh and try again."
        case .invalidResponse:
            return "The device returned an unreadable Wi-Fi configuration."
        case .saveNotConfirmed:
            return "The device did not confirm that the network was saved."
        case .requestFailed:
            return "The device could not save the Wi-Fi changes."
        }
    }
}

protocol WLEDSavedNetworkServicing {
    func loadSnapshot(for device: WLEDDevice) async throws -> WLEDSavedNetworkSnapshot
    func save(
        _ draft: WLEDSavedNetworkDraft,
        for device: WLEDDevice,
        replacingSlot: Int?,
        restartAfterSave: Bool
    ) async throws -> WLEDSavedNetworkMutationResult
    func remove(_ network: WLEDSavedNetwork, from device: WLEDDevice) async throws -> WLEDSavedNetworkMutationResult
}

final class WLEDSavedNetworkObservationStore {
    static let shared = WLEDSavedNetworkObservationStore()

    private struct Record: Codable {
        var notTested: Bool
        var lastConfirmedAt: Date?
    }

    private let defaults: UserDefaults
    private let storageKey = "WLEDSavedNetworkObservationStore.records.v1"
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func status(deviceID: String, ssid: String) -> WLEDSavedNetworkStatus {
        lock.lock()
        defer { lock.unlock() }
        guard let record = records()[key(deviceID: deviceID, ssid: ssid)] else { return .saved }
        return record.notTested ? .notTested : .saved
    }

    func markNotTested(deviceID: String, ssid: String) {
        update(deviceID: deviceID, ssid: ssid, record: Record(notTested: true, lastConfirmedAt: nil))
    }

    func markConnected(deviceID: String, ssid: String, at date: Date = Date()) {
        update(deviceID: deviceID, ssid: ssid, record: Record(notTested: false, lastConfirmedAt: date))
    }

    func remove(deviceID: String, ssid: String) {
        lock.lock()
        defer { lock.unlock() }
        var values = records()
        values.removeValue(forKey: key(deviceID: deviceID, ssid: ssid))
        persist(values)
    }

    private func update(deviceID: String, ssid: String, record: Record) {
        lock.lock()
        defer { lock.unlock() }
        var values = records()
        values[key(deviceID: deviceID, ssid: ssid)] = record
        persist(values)
    }

    private func key(deviceID: String, ssid: String) -> String {
        "\(WLEDDeviceIdentity.canonicalID(for: deviceID))\u{1f}\(ssid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private func records() -> [String: Record] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: Record].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func persist(_ records: [String: Record]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

final class WLEDSavedNetworkService: WLEDSavedNetworkServicing {
    static let shared = WLEDSavedNetworkService()

    private let session: URLSession
    private let observationStore: WLEDSavedNetworkObservationStore
    private let logger = Logger(subsystem: "com.aesdetic.control", category: "SavedWiFi")

    init(
        session: URLSession = .shared,
        observationStore: WLEDSavedNetworkObservationStore = .shared
    ) {
        self.session = session
        self.observationStore = observationStore
    }

    func loadSnapshot(for device: WLEDDevice) async throws -> WLEDSavedNetworkSnapshot {
        async let configRequest = fetchConfig(for: device)
        async let infoRequest = fetchInfo(for: device)
        let config = try await configRequest
        let info = try await infoRequest
        let scannedNetworks = (try? await fetchNetworks(for: device)) ?? []
        return snapshot(
            config: config,
            info: info,
            scannedNetworks: scannedNetworks,
            deviceID: device.id
        )
    }

    func save(
        _ draft: WLEDSavedNetworkDraft,
        for device: WLEDDevice,
        replacingSlot: Int? = nil,
        restartAfterSave: Bool = false
    ) async throws -> WLEDSavedNetworkMutationResult {
        guard draft.isValid else { throw WLEDSavedNetworkError.invalidCredentials }

        let snapshot = try await loadSnapshot(for: device)
        guard snapshot.supportsMultipleNetworks else { throw WLEDSavedNetworkError.unsupportedFirmware }
        let plan = try Self.mutationPlan(
            snapshot: snapshot,
            ssid: draft.normalizedSSID,
            replacingSlot: replacingSlot
        )

        var config = try await fetchConfig(for: device)
        let previousNetwork = network(in: snapshot, for: plan)
        let requiresPasswordClear = draft.isOpenNetwork && previousNetwork?.hasPassword == true
        let usesForm = requiresPasswordClear

        logger.info(
            "wifi.saved.submit device=\(WLEDDeviceIdentity.canonicalID(for: device.id), privacy: .public) ssid=\(draft.normalizedSSID, privacy: .public) restart=\(restartAfterSave) form=\(usesForm)"
        )

        if usesForm {
            let stations = try mutatedStations(in: config, draft: draft, plan: plan)
            try await postWiFiForm(config: config, stations: stations, to: device)
            removeReplacedObservation(previousNetwork, draft: draft, deviceID: device.id)
            observationStore.markNotTested(deviceID: device.id, ssid: draft.normalizedSSID)
            return .requiresRediscovery
        }

        try apply(draft: draft, plan: plan, to: &config)
        config["sv"] = true
        config["rb"] = restartAfterSave
        try await postConfig(config, to: device, restarting: restartAfterSave)
        removeReplacedObservation(previousNetwork, draft: draft, deviceID: device.id)

        if restartAfterSave {
            observationStore.markNotTested(deviceID: device.id, ssid: draft.normalizedSSID)
            return .requiresRediscovery
        }

        let confirmedConfig = try await fetchConfig(for: device)
        let confirmedNetworks = Self.parseNetworks(from: confirmedConfig, deviceID: device.id, observationStore: observationStore)
        guard let confirmed = confirmedNetworks.first(where: {
            $0.ssid.caseInsensitiveCompare(draft.normalizedSSID) == .orderedSame
        }), confirmed.hasPassword == !draft.isOpenNetwork else {
            throw WLEDSavedNetworkError.saveNotConfirmed
        }

        observationStore.markNotTested(deviceID: device.id, ssid: draft.normalizedSSID)
        return .saved(WLEDSavedNetwork(
            slot: confirmed.slot,
            ssid: confirmed.ssid,
            hasPassword: confirmed.hasPassword,
            configuredBSSID: confirmed.configuredBSSID,
            status: .notTested
        ))
    }

    func remove(_ network: WLEDSavedNetwork, from device: WLEDDevice) async throws -> WLEDSavedNetworkMutationResult {
        let snapshot = try await loadSnapshot(for: device)
        guard snapshot.supportsMultipleNetworks else { throw WLEDSavedNetworkError.unsupportedFirmware }
        guard let connectedSlot = snapshot.connectedSlot else { throw WLEDSavedNetworkError.currentNetworkUnknown }
        guard connectedSlot != network.slot else { throw WLEDSavedNetworkError.connectedNetworkProtected }

        let config = try await fetchConfig(for: device)
        var stations = try stationDictionaries(from: config)
        guard stations.indices.contains(network.slot) else { throw WLEDSavedNetworkError.networkNotFound }
        stations.remove(at: network.slot)
        try await postWiFiForm(config: config, stations: stations, to: device)
        observationStore.remove(deviceID: device.id, ssid: network.ssid)
        logger.info(
            "wifi.saved.remove device=\(WLEDDeviceIdentity.canonicalID(for: device.id), privacy: .public) ssid=\(network.ssid, privacy: .public)"
        )
        return .requiresRediscovery
    }

    static func mutationPlan(
        snapshot: WLEDSavedNetworkSnapshot,
        ssid: String,
        replacingSlot: Int?
    ) throws -> WLEDSavedNetworkMutationPlan {
        if let existing = snapshot.networks.first(where: {
            $0.ssid.caseInsensitiveCompare(ssid) == .orderedSame
        }) {
            return .update(slot: existing.slot)
        }

        let nextSlot = (snapshot.networks.map(\.slot).max() ?? -1) + 1
        if nextSlot < snapshot.capacity {
            return .append(slot: nextSlot)
        }

        guard let replacingSlot else { throw WLEDSavedNetworkError.replacementRequired }
        guard snapshot.connectedSlot != nil else { throw WLEDSavedNetworkError.currentNetworkUnknown }
        guard snapshot.networks.contains(where: { $0.slot == replacingSlot }) else {
            throw WLEDSavedNetworkError.networkNotFound
        }
        guard replacingSlot != snapshot.connectedSlot else {
            throw WLEDSavedNetworkError.connectedNetworkProtected
        }
        return .replace(slot: replacingSlot)
    }

    static func strongestNetworksBySSID(_ networks: [WiFiNetwork]) -> [WiFiNetwork] {
        var strongestBySSID: [String: WiFiNetwork] = [:]
        for network in networks {
            let key = network.ssid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }
            if let existing = strongestBySSID[key], existing.signalStrength >= network.signalStrength {
                continue
            }
            strongestBySSID[key] = network
        }
        return strongestBySSID.values.sorted {
            if $0.signalStrength == $1.signalStrength {
                return $0.ssid.localizedCaseInsensitiveCompare($1.ssid) == .orderedAscending
            }
            return $0.signalStrength > $1.signalStrength
        }
    }

    static func parseNetworks(
        from config: [String: Any],
        deviceID: String,
        observationStore: WLEDSavedNetworkObservationStore
    ) -> [WLEDSavedNetwork] {
        let root = (config["cfg"] as? [String: Any]) ?? config
        let networkConfig = root["nw"] as? [String: Any] ?? [:]
        let stations = networkConfig["ins"] as? [[String: Any]] ?? []
        var seen = Set<String>()

        return stations.enumerated().compactMap { slot, station in
            let ssid = string(station["ssid"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ssid.isEmpty else { return nil }
            let key = ssid.lowercased()
            guard seen.insert(key).inserted else { return nil }
            let passwordLength = int(station["pskl"])
            let configuredBSSID = string(station["bssid"])
            return WLEDSavedNetwork(
                slot: slot,
                ssid: ssid,
                hasPassword: passwordLength > 0,
                configuredBSSID: configuredBSSID.isEmpty ? nil : configuredBSSID,
                status: observationStore.status(deviceID: deviceID, ssid: ssid)
            )
        }
    }

    private func snapshot(
        config: [String: Any],
        info: [String: Any],
        scannedNetworks: [WiFiNetwork],
        deviceID: String
    ) -> WLEDSavedNetworkSnapshot {
        var networks = Self.parseNetworks(from: config, deviceID: deviceID, observationStore: observationStore)
        let wifi = info["wifi"] as? [String: Any] ?? [:]
        let connectedBSSID = Self.normalizeBSSID(Self.string(wifi["bssid"]))
        let firmwareVersion = Self.string(info["ver"])
        let signalStrength = Self.optionalInt(wifi["rssi"])

        var connectedSSID: String?
        if !connectedBSSID.isEmpty {
            if let configured = networks.first(where: {
                Self.normalizeBSSID($0.configuredBSSID ?? "") == connectedBSSID
            }) {
                connectedSSID = configured.ssid
            } else if let scanned = scannedNetworks.first(where: {
                Self.normalizeBSSID($0.bssid ?? "") == connectedBSSID
            }) {
                connectedSSID = scanned.ssid
            }
        }

        let connectedSlot = connectedSSID.flatMap { ssid in
            networks.first(where: { $0.ssid.caseInsensitiveCompare(ssid) == .orderedSame })?.slot
        }
        if let connectedSlot,
           let index = networks.firstIndex(where: { $0.slot == connectedSlot }) {
            networks[index].status = .connected
            observationStore.markConnected(deviceID: deviceID, ssid: networks[index].ssid)
        }

        return WLEDSavedNetworkSnapshot(
            networks: networks,
            connectedSlot: connectedSlot,
            connectedSSID: connectedSSID,
            connectedBSSID: connectedBSSID.isEmpty ? nil : connectedBSSID,
            signalStrength: signalStrength,
            firmwareVersion: firmwareVersion.isEmpty ? nil : firmwareVersion,
            capacity: WLEDSavedNetworkSnapshot.stockCapacity
        )
    }

    private func fetchConfig(for device: WLEDDevice) async throws -> [String: Any] {
        try await fetchJSON(path: "/json/cfg", for: device)
    }

    private func fetchInfo(for device: WLEDDevice) async throws -> [String: Any] {
        try await fetchJSON(path: "/json/info", for: device)
    }

    private func fetchJSON(path: String, for device: WLEDDevice) async throws -> [String: Any] {
        guard let url = URL(string: "http://\(device.ipAddress)\(path)") else {
            throw WLEDSavedNetworkError.requestFailed
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WLEDSavedNetworkError.invalidResponse
        }
        return object
    }

    private func fetchNetworks(for device: WLEDDevice) async throws -> [WiFiNetwork] {
        var lastError: Error?
        for attempt in 0..<5 {
            do {
                let networks = try await fetchNetworksOnce(for: device)
                if !networks.isEmpty {
                    return networks
                }
            } catch {
                lastError = error
            }

            if attempt < 4 {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 700_000_000)
            }
        }

        if let lastError { throw lastError }
        return []
    }

    private func fetchNetworksOnce(for device: WLEDDevice) async throws -> [WiFiNetwork] {
        guard let url = URL(string: "http://\(device.ipAddress)/json/net") else {
            throw WLEDSavedNetworkError.requestFailed
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw WLEDSavedNetworkError.requestFailed
        }

        let object = try JSONSerialization.jsonObject(with: data)
        let rows: [[String: Any]]
        if let root = object as? [String: Any], let values = root["networks"] as? [[String: Any]] {
            rows = values
        } else if let values = object as? [[String: Any]] {
            rows = values
        } else {
            throw WLEDSavedNetworkError.invalidResponse
        }

        return rows.compactMap { row in
            let ssid = Self.string(row["ssid"])
            guard !ssid.isEmpty else { return nil }
            let encryption = Self.int(row["enc"])
            return WiFiNetwork(
                ssid: ssid,
                signalStrength: Self.int(row["rssi"]),
                security: encryption == 0 ? "Open" : "Secured",
                channel: Self.int(row["channel"]),
                bssid: Self.string(row["bssid"])
            )
        }
    }

    private func apply(
        draft: WLEDSavedNetworkDraft,
        plan: WLEDSavedNetworkMutationPlan,
        to config: inout [String: Any]
    ) throws {
        var root = (config["cfg"] as? [String: Any]) ?? config
        var networkConfig = root["nw"] as? [String: Any] ?? [:]
        var stations = networkConfig["ins"] as? [[String: Any]] ?? []
        let slot = Self.slot(for: plan)

        var station: [String: Any]
        if case .update = plan, stations.indices.contains(slot) {
            station = stations[slot]
        } else {
            station = [
                "ip": [0, 0, 0, 0],
                "gw": [0, 0, 0, 0],
                "sn": [255, 255, 255, 0],
                "bssid": ""
            ]
        }
        station["ssid"] = draft.normalizedSSID
        station.removeValue(forKey: "pskl")
        if draft.isOpenNetwork {
            station.removeValue(forKey: "psk")
        } else {
            station["psk"] = draft.password
        }

        switch plan {
        case .append:
            stations.append(station)
        case .update, .replace:
            guard stations.indices.contains(slot) else { throw WLEDSavedNetworkError.networkNotFound }
            stations[slot] = station
        }

        networkConfig["ins"] = stations
        root["nw"] = networkConfig
        if config["cfg"] != nil {
            config["cfg"] = root
        } else {
            config = root
        }
    }

    private func mutatedStations(
        in config: [String: Any],
        draft: WLEDSavedNetworkDraft,
        plan: WLEDSavedNetworkMutationPlan
    ) throws -> [[String: Any]] {
        var stations = try stationDictionaries(from: config)
        let slot = Self.slot(for: plan)
        var station = (plan.isUpdate && stations.indices.contains(slot)) ? stations[slot] : [
            "ip": [0, 0, 0, 0],
            "gw": [0, 0, 0, 0],
            "sn": [255, 255, 255, 0],
            "bssid": ""
        ]
        station["ssid"] = draft.normalizedSSID
        station["pskl"] = draft.isOpenNetwork ? 0 : draft.password.count
        station.removeValue(forKey: "psk")

        switch plan {
        case .append:
            stations.append(station)
        case .update, .replace:
            guard stations.indices.contains(slot) else { throw WLEDSavedNetworkError.networkNotFound }
            stations[slot] = station
        }
        return stations
    }

    private func stationDictionaries(from config: [String: Any]) throws -> [[String: Any]] {
        let root = (config["cfg"] as? [String: Any]) ?? config
        guard let networkConfig = root["nw"] as? [String: Any],
              let stations = networkConfig["ins"] as? [[String: Any]] else {
            throw WLEDSavedNetworkError.invalidResponse
        }
        return stations
    }

    private func postConfig(_ config: [String: Any], to device: WLEDDevice, restarting: Bool) async throws {
        guard let url = URL(string: "http://\(device.ipAddress)/json/cfg") else {
            throw WLEDSavedNetworkError.requestFailed
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = restarting ? WLEDWiFiService.provisioningRestartResponseTimeout : 12
        request.httpBody = try JSONSerialization.data(withJSONObject: config)
        do {
            let (_, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw WLEDSavedNetworkError.requestFailed
            }
        } catch where restarting && WLEDSafeWiFiChangeService.isExpectedRestartInterruption(error) {
            return
        }
    }

    private func postWiFiForm(
        config: [String: Any],
        stations: [[String: Any]],
        to device: WLEDDevice
    ) async throws {
        guard let url = URL(string: "http://\(device.ipAddress)/settings/wifi") else {
            throw WLEDSavedNetworkError.requestFailed
        }
        let originalRoot = (config["cfg"] as? [String: Any]) ?? config
        var root = originalRoot
        var networkConfig = root["nw"] as? [String: Any] ?? [:]
        networkConfig["ins"] = stations
        root["nw"] = networkConfig

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = WLEDWiFiService.provisioningRestartResponseTimeout
        request.httpBody = Self.formEncodedData(Self.wifiFormValues(from: root))
        do {
            let (_, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, (200...399).contains(response.statusCode) else {
                throw WLEDSavedNetworkError.requestFailed
            }
        } catch where WLEDSafeWiFiChangeService.isExpectedRestartInterruption(error) {
            return
        }
    }

    private func network(
        in snapshot: WLEDSavedNetworkSnapshot,
        for plan: WLEDSavedNetworkMutationPlan
    ) -> WLEDSavedNetwork? {
        switch plan {
        case .append:
            return nil
        case .update(let slot), .replace(let slot):
            return snapshot.networks.first(where: { $0.slot == slot })
        }
    }

    private func removeReplacedObservation(
        _ previousNetwork: WLEDSavedNetwork?,
        draft: WLEDSavedNetworkDraft,
        deviceID: String
    ) {
        guard let previousNetwork,
              previousNetwork.ssid.caseInsensitiveCompare(draft.normalizedSSID) != .orderedSame else { return }
        observationStore.remove(deviceID: deviceID, ssid: previousNetwork.ssid)
    }

    private static func slot(for plan: WLEDSavedNetworkMutationPlan) -> Int {
        switch plan {
        case .update(let slot), .append(let slot), .replace(let slot):
            return slot
        }
    }

    private static func wifiFormValues(from root: [String: Any]) -> [(String, String)] {
        let networkConfig = root["nw"] as? [String: Any] ?? [:]
        let stations = networkConfig["ins"] as? [[String: Any]] ?? []
        var values: [(String, String)] = []

        for (slot, station) in stations.enumerated() {
            values.append(("CS\(slot)", string(station["ssid"])))
            values.append(("PW\(slot)", String(repeating: "*", count: int(station["pskl"]))))
            values.append(("BS\(slot)", string(station["bssid"])))
            appendIPv4(station["ip"], prefix: "IP\(slot)", to: &values)
            appendIPv4(station["gw"], prefix: "GW\(slot)", to: &values)
            appendIPv4(station["sn"], prefix: "SN\(slot)", to: &values)
            if station["enc_type"] != nil {
                values.append(("ET\(slot)", String(int(station["enc_type"]))))
                values.append(("EA\(slot)", string(station["e_anon_ident"])))
                values.append(("EI\(slot)", string(station["e_ident"])))
            }
        }

        appendIPv4(networkConfig["dns"], prefix: "D", to: &values)
        values.append(("CM", string((root["id"] as? [String: Any])?["mdns"])))

        let ap = root["ap"] as? [String: Any] ?? [:]
        values.append(("AS", string(ap["ssid"])))
        values.append(("AP", String(repeating: "*", count: int(ap["pskl"]))))
        values.append(("AC", String(int(ap["chan"]))))
        values.append(("AB", String(int(ap["behav"]))))
        if bool(ap["hide"]) { values.append(("AH", "on")) }

        let wifi = root["wifi"] as? [String: Any] ?? [:]
        values.append(("TX", String(optionalInt(wifi["txpwr"]) ?? 78)))
        if bool(wifi["phy"]) { values.append(("FG", "on")) }
        if !bool(wifi["sleep"], default: true) { values.append(("WS", "on")) }
        if bool(networkConfig["espnow"]) { values.append(("RE", "on")) }
        if let remotes = networkConfig["linked_remote"] as? [String] {
            for (index, remote) in remotes.prefix(10).enumerated() {
                values.append(("RM\(index)", remote))
            }
        }
        if let ethernetType = optionalInt((root["eth"] as? [String: Any])?["type"]) {
            values.append(("ETH", String(ethernetType)))
        }
        return values
    }

    private static func appendIPv4(_ value: Any?, prefix: String, to values: inout [(String, String)]) {
        let parts = value as? [Any] ?? []
        for index in 0..<4 {
            values.append(("\(prefix)\(index)", String(index < parts.count ? int(parts[index]) : 0)))
        }
    }

    private static func formEncodedData(_ values: [(String, String)]) -> Data {
        var components = URLComponents()
        components.queryItems = values.map { URLQueryItem(name: $0.0, value: $0.1) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    static func normalizeBSSID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private static func string(_ value: Any?) -> String {
        if let value = value as? String { return value.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let value = value as? NSNumber { return value.stringValue }
        return ""
    }

    private static func int(_ value: Any?) -> Int {
        optionalInt(value) ?? 0
    }

    private static func optionalInt(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private static func bool(_ value: Any?, default defaultValue: Bool = false) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            switch value.lowercased() {
            case "true", "1", "on": return true
            case "false", "0", "off": return false
            default: break
            }
        }
        return defaultValue
    }
}

private extension WLEDSavedNetworkMutationPlan {
    var isUpdate: Bool {
        if case .update = self { return true }
        return false
    }
}
