import Foundation
import Testing
@testable import Aesdetic_Control

private final class SavedNetworkURLProtocol: URLProtocol {
    typealias Handler = (URLRequest, Data?) throws -> (HTTPURLResponse, Data)
    static var handler: Handler?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        do {
            let body = request.httpBody ?? Self.read(stream: request.httpBodyStream)
            let (response, data) = try Self.handler?(request, body) ?? {
                throw URLError(.badServerResponse)
            }()
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    private static func read(stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

@Suite(.serialized)
struct WLEDSavedNetworkServiceTests {
    @Test func credentialDraftValidatesSecuredOpenAndHexPasswords() {
        #expect(!WLEDSavedNetworkDraft(ssid: "Home", password: "short", isOpenNetwork: false).isValid)
        #expect(WLEDSavedNetworkDraft(ssid: "Home", password: "password1", isOpenNetwork: false).isValid)
        #expect(WLEDSavedNetworkDraft(ssid: "Guest", password: "", isOpenNetwork: true).isValid)
        #expect(WLEDSavedNetworkDraft(
            ssid: "Home",
            password: String(repeating: "a", count: 64),
            isOpenNetwork: false
        ).isValid)
        #expect(!WLEDSavedNetworkDraft(
            ssid: "Home",
            password: String(repeating: "z", count: 64),
            isOpenNetwork: false
        ).isValid)

        var transientDraft = WLEDSavedNetworkDraft(
            ssid: "Home",
            password: "never-persist-this",
            isOpenNetwork: false
        )
        transientDraft.clearSensitiveValues()
        #expect(transientDraft.password.isEmpty)
    }

    @Test func parserReadsWrappedStationsAndDeduplicatesSSIDWithoutChangingSlots() throws {
        let store = makeObservationStore()
        let config: [String: Any] = [
            "cfg": [
                "nw": [
                    "ins": [
                        ["ssid": "Home", "pskl": 10, "bssid": "AABBCCDDEEFF"],
                        ["ssid": "Backup", "pskl": 0],
                        ["ssid": "home", "pskl": 12]
                    ]
                ]
            ]
        ]

        let networks = WLEDSavedNetworkService.parseNetworks(
            from: config,
            deviceID: "AA:BB:CC:DD:EE:FF",
            observationStore: store
        )

        #expect(networks.count == 2)
        #expect(networks[0].slot == 0)
        #expect(networks[0].hasPassword)
        #expect(networks[1].slot == 1)
        #expect(!networks[1].hasPassword)
    }

    @Test func addNetworkScanKeepsStrongestAccessPointPerSSID() {
        let networks = WLEDSavedNetworkService.strongestNetworksBySSID([
            WiFiNetwork(
                ssid: "Home Mesh",
                signalStrength: -72,
                security: "WPA2",
                channel: 1,
                bssid: "AA:AA:AA:AA:AA:AA"
            ),
            WiFiNetwork(
                ssid: "home mesh",
                signalStrength: -41,
                security: "WPA2",
                channel: 6,
                bssid: "BB:BB:BB:BB:BB:BB"
            ),
            WiFiNetwork(
                ssid: "Guest",
                signalStrength: -55,
                security: "Open",
                channel: 11,
                bssid: nil
            )
        ])

        #expect(networks.count == 2)
        #expect(networks[0].ssid.caseInsensitiveCompare("home mesh") == .orderedSame)
        #expect(networks[0].signalStrength == -41)
        #expect(networks[1].ssid == "Guest")
    }

    @Test func capacityPlannerRequiresExplicitNonCurrentReplacement() throws {
        let snapshot = makeSnapshot(
            networks: [
                saved(slot: 0, ssid: "Home", status: .connected),
                saved(slot: 1, ssid: "Office"),
                saved(slot: 2, ssid: "Studio")
            ],
            connectedSlot: 0
        )

        #expect(try WLEDSavedNetworkService.mutationPlan(
            snapshot: snapshot,
            ssid: "Office",
            replacingSlot: nil
        ) == .update(slot: 1))
        #expect(throws: WLEDSavedNetworkError.replacementRequired) {
            try WLEDSavedNetworkService.mutationPlan(snapshot: snapshot, ssid: "New", replacingSlot: nil)
        }
        #expect(throws: WLEDSavedNetworkError.connectedNetworkProtected) {
            try WLEDSavedNetworkService.mutationPlan(snapshot: snapshot, ssid: "New", replacingSlot: 0)
        }
        #expect(try WLEDSavedNetworkService.mutationPlan(
            snapshot: snapshot,
            ssid: "New",
            replacingSlot: 2
        ) == .replace(slot: 2))
    }

    @Test func duplicateSlotsNeverCauseAppendToOverwriteOccupiedSlot() {
        let snapshot = makeSnapshot(
            networks: [
                saved(slot: 0, ssid: "Home", status: .connected),
                saved(slot: 2, ssid: "Office")
            ],
            connectedSlot: 0
        )

        #expect(throws: WLEDSavedNetworkError.replacementRequired) {
            try WLEDSavedNetworkService.mutationPlan(snapshot: snapshot, ssid: "New", replacingSlot: nil)
        }
    }

    @Test func securedAlternateSavePreservesConfigAndDoesNotRestart() async throws {
        let store = makeObservationStore()
        var config = Self.baseConfig()
        var postedConfig: [String: Any]?
        let service = makeService(store: store) { request, body in
            let response = try Self.response(request)
            switch (request.url?.path, request.httpMethod) {
            case ("/json/cfg", "POST"):
                let postedBody = try #require(body)
                let postedObject = try JSONSerialization.jsonObject(with: postedBody)
                let posted = try #require(postedObject as? [String: Any])
                postedConfig = posted
                config = Self.serializedReadback(from: posted)
                return (response, Data(#"{"success":true}"#.utf8))
            case ("/json/cfg", _):
                return (response, try JSONSerialization.data(withJSONObject: config))
            case ("/json/info", _):
                return (response, Self.infoData())
            case ("/json/net", _):
                return (response, Self.networkData())
            default:
                throw URLError(.badURL)
            }
        }

        let result = try await service.save(
            WLEDSavedNetworkDraft(ssid: "Studio", password: "studio-pass", isOpenNetwork: false),
            for: Self.device(),
            replacingSlot: nil,
            restartAfterSave: false
        )

        guard case .saved(let savedNetwork) = result else {
            Issue.record("Expected a confirmed non-restarting save")
            return
        }
        #expect(savedNetwork.ssid == "Studio")
        let posted = try #require(postedConfig)
        #expect(posted["sv"] as? Bool == true)
        #expect(posted["rb"] as? Bool == false)
        let stations = try #require((posted["nw"] as? [String: Any])?["ins"] as? [[String: Any]])
        #expect(stations.count == 3)
        #expect(stations[0]["ssid"] as? String == "Home")
        #expect(stations[1]["ssid"] as? String == "Backup")
        #expect(stations[2]["ssid"] as? String == "Studio")
        #expect(stations[2]["psk"] as? String == "studio-pass")
    }

    @Test func connectedSSIDIsResolvedOnlyFromCurrentBSSID() async throws {
        let service = makeService(store: makeObservationStore()) { request, _ in
            let response = try Self.response(request)
            switch request.url?.path {
            case "/json/cfg": return (response, try JSONSerialization.data(withJSONObject: Self.baseConfig()))
            case "/json/info": return (response, Self.infoData())
            case "/json/net": return (response, Self.networkData())
            default: throw URLError(.badURL)
            }
        }

        let snapshot = try await service.loadSnapshot(for: Self.device())

        #expect(snapshot.connectedSSID == "Home")
        #expect(snapshot.connectedSlot == 0)
        #expect(snapshot.networks.first?.status == .connected)
    }

    @Test func connectedSSIDResolutionRetriesAnInitiallyEmptyScan() async throws {
        var scanCount = 0
        let service = makeService(store: makeObservationStore()) { request, _ in
            let response = try Self.response(request)
            switch request.url?.path {
            case "/json/cfg":
                return (response, try JSONSerialization.data(withJSONObject: Self.baseConfig()))
            case "/json/info":
                return (response, Self.infoData())
            case "/json/net":
                scanCount += 1
                return (response, scanCount == 1 ? Data(#"{"networks":[]}"#.utf8) : Self.networkData())
            default:
                throw URLError(.badURL)
            }
        }

        let snapshot = try await service.loadSnapshot(for: Self.device())

        #expect(scanCount == 2)
        #expect(snapshot.connectedSSID == "Home")
    }

    @Test func openAlternateSaveDoesNotSendAPasswordOrRestart() async throws {
        var config = Self.baseConfig()
        var postedConfig: [String: Any]?
        let service = makeService(store: makeObservationStore()) { request, body in
            let response = try Self.response(request)
            switch (request.url?.path, request.httpMethod) {
            case ("/json/cfg", "POST"):
                let postedBody = try #require(body)
                let object = try JSONSerialization.jsonObject(with: postedBody)
                let posted = try #require(object as? [String: Any])
                postedConfig = posted
                config = Self.serializedReadback(from: posted)
                return (response, Data(#"{"success":true}"#.utf8))
            case ("/json/cfg", _):
                return (response, try JSONSerialization.data(withJSONObject: config))
            case ("/json/info", _):
                return (response, Self.infoData())
            case ("/json/net", _):
                return (response, Self.networkData())
            default:
                throw URLError(.badURL)
            }
        }

        let result = try await service.save(
            WLEDSavedNetworkDraft(ssid: "Guest", password: "", isOpenNetwork: true),
            for: Self.device(),
            replacingSlot: nil,
            restartAfterSave: false
        )

        guard case .saved(let network) = result else {
            Issue.record("Expected the open network save to be confirmed")
            return
        }
        #expect(!network.hasPassword)
        let posted = try #require(postedConfig)
        #expect(posted["rb"] as? Bool == false)
        let stations = try #require((posted["nw"] as? [String: Any])?["ins"] as? [[String: Any]])
        #expect(stations[2]["ssid"] as? String == "Guest")
        #expect(stations[2]["psk"] == nil)
    }

    @Test func removalUsesCompleteFormAndPreservesMaskedPasswords() async throws {
        var submittedForm: [String: String] = [:]
        let service = makeService(store: makeObservationStore()) { request, body in
            let response = try Self.response(request)
            switch (request.url?.path, request.httpMethod) {
            case ("/settings/wifi", "POST"):
                submittedForm = Self.decodeForm(try #require(body))
                return (response, Data("Saved".utf8))
            case ("/json/cfg", _):
                return (response, try JSONSerialization.data(withJSONObject: Self.baseConfig()))
            case ("/json/info", _): return (response, Self.infoData())
            case ("/json/net", _): return (response, Self.networkData())
            default: throw URLError(.badURL)
            }
        }

        let result = try await service.remove(saved(slot: 1, ssid: "Backup"), from: Self.device())

        #expect(result == .requiresRediscovery)
        #expect(submittedForm["CS0"] == "Home")
        #expect(submittedForm["PW0"] == String(repeating: "*", count: 10))
        #expect(submittedForm["CS1"] == nil)
        #expect(submittedForm["AS"] == "WLED-AP")
        #expect(submittedForm["AP"] == String(repeating: "*", count: 8))
    }

    private func makeService(
        store: WLEDSavedNetworkObservationStore,
        handler: @escaping SavedNetworkURLProtocol.Handler
    ) -> WLEDSavedNetworkService {
        SavedNetworkURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SavedNetworkURLProtocol.self]
        return WLEDSavedNetworkService(
            session: URLSession(configuration: configuration),
            observationStore: store
        )
    }

    private func makeObservationStore() -> WLEDSavedNetworkObservationStore {
        let name = "WLEDSavedNetworkServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return WLEDSavedNetworkObservationStore(defaults: defaults)
    }

    private func makeSnapshot(
        networks: [WLEDSavedNetwork],
        connectedSlot: Int?
    ) -> WLEDSavedNetworkSnapshot {
        WLEDSavedNetworkSnapshot(
            networks: networks,
            connectedSlot: connectedSlot,
            connectedSSID: connectedSlot.flatMap { slot in networks.first(where: { $0.slot == slot })?.ssid },
            connectedBSSID: connectedSlot == nil ? nil : "aabbccddeeff",
            signalStrength: -42,
            firmwareVersion: "0.15.1",
            capacity: 3
        )
    }

    private func saved(
        slot: Int,
        ssid: String,
        status: WLEDSavedNetworkStatus = .saved
    ) -> WLEDSavedNetwork {
        WLEDSavedNetwork(
            slot: slot,
            ssid: ssid,
            hasPassword: true,
            configuredBSSID: slot == 0 ? "AABBCCDDEEFF" : nil,
            status: status
        )
    }

    private static func baseConfig() -> [String: Any] {
        [
            "id": ["mdns": "living-room"],
            "nw": [
                "ins": [
                    ["ssid": "Home", "pskl": 10, "bssid": "AABBCCDDEEFF", "ip": [0, 0, 0, 0], "gw": [0, 0, 0, 0], "sn": [255, 255, 255, 0]],
                    ["ssid": "Backup", "pskl": 12, "bssid": "", "ip": [0, 0, 0, 0], "gw": [0, 0, 0, 0], "sn": [255, 255, 255, 0]]
                ],
                "dns": [1, 1, 1, 1]
            ],
            "ap": ["ssid": "WLED-AP", "pskl": 8, "chan": 6, "hide": false, "behav": 1],
            "wifi": ["sleep": false, "phy": false, "txpwr": 78]
        ]
    }

    private static func serializedReadback(from posted: [String: Any]) -> [String: Any] {
        var readback = posted
        var networkConfig = readback["nw"] as? [String: Any] ?? [:]
        var stations = networkConfig["ins"] as? [[String: Any]] ?? []
        for index in stations.indices {
            if let password = stations[index].removeValue(forKey: "psk") as? String {
                stations[index]["pskl"] = password.count
            }
        }
        networkConfig["ins"] = stations
        readback["nw"] = networkConfig
        return readback
    }

    private static func infoData() -> Data {
        Data(#"{"ver":"0.15.1","wifi":{"bssid":"AA:BB:CC:DD:EE:FF","rssi":-42}}"#.utf8)
    }

    private static func networkData() -> Data {
        Data(#"{"networks":[{"ssid":"Home","bssid":"AA:BB:CC:DD:EE:FF","rssi":-42,"enc":3,"channel":6}]}"#.utf8)
    }

    private static func response(_ request: URLRequest) throws -> HTTPURLResponse {
        let url = try #require(request.url)
        return try #require(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
    }

    private static func decodeForm(_ data: Data) -> [String: String] {
        let raw = String(data: data, encoding: .utf8) ?? ""
        return raw.split(separator: "&").reduce(into: [:]) { result, pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(parts[0]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? ""
            let value = parts.count > 1
                ? (String(parts[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? "")
                : ""
            result[key] = value
        }
    }

    private static func device() -> WLEDDevice {
        WLEDDevice(
            id: "AA:BB:CC:DD:EE:FF",
            name: "Test Device",
            ipAddress: "192.168.1.20",
            isOnline: true,
            brightness: 128,
            currentColor: .white,
            productType: .generic,
            location: .all,
            lastSeen: Date(),
            state: nil
        )
    }
}
