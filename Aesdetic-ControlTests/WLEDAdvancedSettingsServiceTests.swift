import Foundation
import SwiftUI
import Testing
@testable import Aesdetic_Control

private final class MockAdvancedWLEDURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    private static var handler: Handler?
    private static var recordedRequests: [URLRequest] = []
    private static var recordedBodies: [Data?] = []

    static func reset(handler: @escaping Handler) {
        lock.lock()
        self.handler = handler
        recordedRequests = []
        recordedBodies = []
        lock.unlock()
    }

    static func requests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }

    static func requestBodies() -> [Data?] {
        lock.lock()
        defer { lock.unlock() }
        return recordedBodies
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let body = bodyData(from: request)
        Self.lock.lock()
        Self.recordedRequests.append(request)
        Self.recordedBodies.append(body)
        let handler = Self.handler
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    private func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }
        return data
    }
}

@Suite(.serialized)
struct WLEDAdvancedSettingsServiceTests {
    @Test func supportedFeaturesUseLiveJSONCapabilitiesInsteadOfHiddenWebPageText() async throws {
        let service = makeService { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }

            switch url.path {
            case "/json/cfg":
                return (
                    response,
                    Data(#"{"nw":{"espnow":false},"if":{"sync":{"espnow":false},"live":{"dmx":{"inputRxPin":-1,"inputTxPin":-1,"inputEnablePin":-1,"dmxInputPort":2}}}}"#.utf8)
                )
            case "/json/info":
                return (response, Data(#"{"leds":{"cct":true,"seglc":[7]}}"#.utf8))
            default:
                Issue.record("Unexpected capability request: \(url.path)")
                throw URLError(.badURL)
            }
        }

        let features = try await service.fetchSupportedAdvancedFeatures(for: testDevice())

        #expect(features.contains("WLED_ENABLE_ESPNOW"))
        #expect(features.contains("WLED_ENABLE_DMX_INPUT"))
        #expect(features.contains("WLED_ENABLE_CCT_OUTPUT"))
        #expect(!features.contains("WLED_ENABLE_DMX"))
    }

    @Test func manifestContainsCurrentWLEDCategoriesAndFields() async throws {
        let manifest = try await WLEDAdvancedSettingsService().loadManifest()

        #expect(manifest.categories.map(\.title) == [
            "WiFi & Network",
            "LED & Hardware",
            "Pin Info",
            "2D Configuration",
            "User Interface",
            "DMX Output",
            "Sync Interfaces",
            "Time & Macros",
            "Usermods",
            "Security & Updates"
        ])
        #expect(manifest.categories.reduce(0) { $0 + $1.sourceFieldCount } == 191)
        #expect(manifest.category(id: "led-hardware")?.fields.contains { $0.key == "BF" && $0.configPath == "light.scale-bri" } == true)
        #expect(manifest.category(id: "sync-interfaces")?.fields.contains { $0.key == "MQPASS" && $0.secret } == true)
        #expect(manifest.category(id: "sync-interfaces")?.fields.contains { $0.key == "MS" && $0.configPath == "if.mqtt.broker" } == true)
        #expect(manifest.category(id: "sync-interfaces")?.fields.contains { $0.key == "HL" && $0.configPath == "if.hue.id" } == true)
        #expect(manifest.category(id: "sync-interfaces")?.fields.contains { $0.key == "HI" && $0.configPath == "if.hue.iv" } == true)
        #expect(manifest.category(id: "sync-interfaces")?.fields.contains { $0.key == "HP" && $0.configPath == "if.hue.en" } == true)
        #expect(manifest.category(id: "sync-interfaces")?.fields.contains { $0.key == "IDMR" && $0.configPath == "if.live.dmx.inputRxPin" } == true)
        #expect(manifest.category(id: "sync-interfaces")?.fields.contains { $0.key == "BD" && $0.configPath == "hw.baud" } == true)
        #expect(manifest.category(id: "sync-interfaces")?.fields.contains { $0.key == "DI" && $0.localOnly } == true)
        #expect(manifest.category(id: "wifi-network")?.fields.contains { $0.key == "CM" && $0.configPath == "id.mdns" } == true)
        #expect(manifest.category(id: "time-macros")?.fields.contains { $0.key == "CM" && $0.configPath == "timers.cntdwn.goal[4]" } == true)
        #expect(manifest.category(id: "time-macros")?.fields.contains { $0.key == "O2" && $0.configPath == "ol.max" } == true)
        #expect(manifest.category(id: "time-macros")?.fields.contains { $0.key == "CE" && $0.configPath == "ol.cntdwn" } == true)
        #expect(manifest.category(id: "security-updates")?.fields.contains { $0.key == "PIN" && $0.secret } == true)
        #expect(manifest.category(id: "security-updates")?.fields.contains { $0.key == "NO" && $0.configPath == "ota.lock" } == true)
        #expect(manifest.category(id: "security-updates")?.fields.contains { $0.key == "RS" && $0.localOnly } == true)
        #expect(manifest.category(id: "dmx-output")?.fields.contains { $0.key == "CS" && $0.configPath == "dmx.start" } == true)
        #expect(manifest.category(id: "2d-configuration")?.readOnly == true)
    }

    @Test func securityUpdatesDraftUsesWLEDSecurityFormAndNeverPostsFactoryReset() async throws {
        var config: [String: Any] = [
            "ota": [
                "lock": false,
                "lock-wifi": false,
                "pskl": 10,
                "aota": false,
                "same-subnet": true
            ]
        ]
        var formPost: [String: String] = [:]

        let service = makeService { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }

            if request.httpMethod == "POST", url.path == "/settings/sec" {
                let body = try #require(MockAdvancedWLEDURLProtocol.requestBodies().last ?? nil)
                formPost = decodedFormValues(from: body)
                #expect(formPost["PIN"] == "0000")
                #expect(formPost["OP"] == "ota-pass")
                #expect(formPost["NO"] == "on")
                #expect(formPost["OW"] == "on")
                #expect(formPost["AO"] == "on")
                #expect(formPost["SU"] == nil)
                #expect(formPost["RS"] == nil)

                var ota = config["ota"] as? [String: Any] ?? [:]
                ota["lock"] = formPost["NO"] == "on"
                ota["lock-wifi"] = formPost["OW"] == "on"
                ota["aota"] = formPost["AO"] == "on"
                ota["same-subnet"] = formPost["SU"] == "on"
                ota["pskl"] = formPost["OP"]?.count ?? 0
                config["ota"] = ota
                return (response, Data("Security settings saved.".utf8))
            }

            if request.httpMethod == "POST" {
                Issue.record("Expected Security & Updates to use /settings/sec, got \(url.path)")
                throw URLError(.badURL)
            }

            let data = try JSONSerialization.data(withJSONObject: config)
            return (response, data)
        }

        let device = testDevice()
        var draft = try await service.fetchDraft(categoryID: "security-updates", for: device)
        #expect(draft.values["NO"] == .bool(false))
        #expect(draft.values["OW"] == .bool(false))
        #expect(draft.values["AO"] == .bool(false))
        #expect(draft.values["SU"] == .bool(true))
        #expect(draft.secretStates["OP"] == .preserve(configured: false))

        draft.setValue(.bool(true), for: "NO")
        draft.setValue(.bool(true), for: "OW")
        draft.setValue(.bool(true), for: "AO")
        draft.setValue(.bool(false), for: "SU")
        draft.setSecretState(.replace("ota-pass"), for: "OP")

        let result = try await service.saveDraft(draft, for: device)

        #expect(result.savedKeys == ["NO", "OW", "AO", "SU", "OP"])
        #expect(result.statusText == "Restart Required")
        #expect((config["ota"] as? [String: Any])?["lock"] as? Bool == true)
        #expect((config["ota"] as? [String: Any])?["same-subnet"] as? Bool == false)

        draft.setSecretState(.replace("123"), for: "PIN")
        #expect(draft.validationErrors()["PIN"] == "Settings PIN must be a 4 digit number.")
    }

    @Test func factoryResetPostsOnlyResetFlag() async throws {
        var capturedForm: [String: String] = [:]
        let service = makeService { request in
            let url = try #require(request.url)
            #expect(request.httpMethod == "POST")
            #expect(url.path == "/settings/sec")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")

            let body = try #require(MockAdvancedWLEDURLProtocol.requestBodies().last ?? nil)
            capturedForm = decodedFormValues(from: body)

            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/plain"]
            ))
            return (response, Data("All Settings erased.".utf8))
        }

        try await service.factoryReset(testDevice())

        #expect(capturedForm == ["RS": "on"])
    }

    @Test func securityUpdatesAboutInfoUsesWLEDJsonInfo() async throws {
        let service = makeService { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }

            #expect(url.path == "/json/info")
            return (response, Data(#"{"ver":"16.0.0","vid":2605030,"brand":"WLED","product":"ESP32","arch":"esp32","core":"v3.1.3","freeheap":123456,"uptime":3661}"#.utf8))
        }

        let info = try await service.fetchSecurityAboutInfo(for: testDevice())

        #expect(info.installedVersionText == "WLED 16.0.0 (2605030)")
        #expect(info.boardText == "ESP32 esp32")
        #expect(info.brand == "WLED")
        #expect(info.core == "v3.1.3")
        #expect(info.freeHeap == 123456)
        #expect(info.uptime == 3661)
    }

    @Test func usermodsDraftUsesWLEDUsermodsFormForGlobalPins() async throws {
        var config: [String: Any] = [
            "hw": [
                "if": [
                    "i2c-pin": [21, 22],
                    "spi-pin": [23, 18, 19]
                ]
            ],
            "um": [
                "Display": [
                    "enabled": true,
                    "pin": 4
                ]
            ]
        ]
        var formPost: [String: String] = [:]

        let service = makeService { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }

            if request.httpMethod == "POST", url.path == "/settings/um" {
                let body = try #require(MockAdvancedWLEDURLProtocol.requestBodies().last ?? nil)
                formPost = decodedFormValues(from: body)
                #expect(formPost["SDA"] == "-1")
                #expect(formPost["SCL"] == "-1")
                #expect(formPost["MOSI"] == "23")
                #expect(formPost["MISO"] == "19")
                #expect(formPost["SCLK"] == "18")
                #expect(formPost["RBT"] == "on")
                // WLED parses every installed Usermod from this single form. Sending
                // only global pins would drop dynamic Usermod state on some firmware.
                #expect(formPost["Display:enabled"] == "true")
                #expect(formPost["Display:pin"] == "4")

                config["hw"] = [
                    "if": [
                        "i2c-pin": [-1, -1],
                        "spi-pin": [23, 18, 19]
                    ]
                ]
                return (response, Data("Usermod settings saved.".utf8))
            }

            if request.httpMethod == "POST" {
                Issue.record("Expected Usermods category to use /settings/um, got \(url.path)")
                throw URLError(.badURL)
            }

            let data = try JSONSerialization.data(withJSONObject: config)
            return (response, data)
        }

        var draft = try await service.fetchDraft(categoryID: "usermods", for: testDevice())
        #expect(draft.values["SDA"] == .number(21))
        #expect(draft.values["SCL"] == .number(22))
        #expect(draft.values["RBT"] == .bool(false))

        draft.setValue(.number(-1), for: "SDA")
        draft.setValue(.number(-1), for: "SCL")
        draft.setValue(.bool(true), for: "RBT")

        let result = try await service.saveDraft(draft, for: testDevice())

        #expect(result.savedKeys == ["SDA", "SCL", "RBT"])
        #expect(result.statusText == "Restart Required")
        #expect(formPost["SDA"] == "-1")
    }

    @Test func usermodsDraftSavesAudioReactiveWithWLEDTypedFormValues() async throws {
        var config: [String: Any] = [
            "hw": [
                "if": [
                    "i2c-pin": [-1, -1],
                    "spi-pin": [-1, -1, -1]
                ]
            ],
            "um": [
                "AudioReactive": [
                    "enabled": false,
                    "add-palettes": false,
                    "analogmic": ["pin": -1],
                    "digitalmic": ["type": 1, "pin": [32, 15, 14, -1]],
                    "config": ["squelch": 10, "gain": 60, "AGC": 0],
                    "frequency": ["scale": 3],
                    "dynamics": ["limiter": true, "rise": 80, "fall": 1400],
                    "sync": ["port": 11988, "mode": 0]
                ]
            ]
        ]
        var submittedEntries: [(String, String)] = []

        let service = makeService { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }

            if request.httpMethod == "POST", url.path == "/settings/um" {
                let body = try #require(MockAdvancedWLEDURLProtocol.requestBodies().last ?? nil)
                submittedEntries = decodedFormEntries(from: body)

                #expect(submittedEntries.contains(where: { $0.0 == "AudioReactive:enabled" && $0.1 == "false" }))
                #expect(submittedEntries.contains(where: { $0.0 == "AudioReactive:enabled" && $0.1 == "true" }))
                #expect(submittedEntries.contains(where: { $0.0 == "AudioReactive:config:gain" && $0.1 == "number" }))
                #expect(submittedEntries.contains(where: { $0.0 == "AudioReactive:config:gain" && $0.1 == "72" }))
                #expect(submittedEntries.filter { $0.0 == "AudioReactive:digitalmic:pin[]" }.map(\.1) == ["32", "15", "14", "-1"])

                var usermods = config["um"] as? [String: Any] ?? [:]
                var audioReactive = usermods["AudioReactive"] as? [String: Any] ?? [:]
                audioReactive["enabled"] = true
                var audioConfig = audioReactive["config"] as? [String: Any] ?? [:]
                audioConfig["gain"] = 72
                audioReactive["config"] = audioConfig
                usermods["AudioReactive"] = audioReactive
                config["um"] = usermods
                return (response, Data("Usermod settings saved.".utf8))
            }

            #expect(request.httpMethod == "GET")
            #expect(url.path == "/json/cfg")
            return (response, try JSONSerialization.data(withJSONObject: config))
        }

        let settingsDraft = try await service.fetchDraft(categoryID: "usermods", for: testDevice())
        var usermodsDraft = try await service.fetchUsermodsDraft(for: testDevice())
        let audioReactiveIndex = try #require(usermodsDraft.modules.firstIndex(where: { $0.name == "AudioReactive" }))
        let enabledIndex = try #require(usermodsDraft.modules[audioReactiveIndex].fields.firstIndex(where: { $0.id == "AudioReactive:enabled" }))
        let gainIndex = try #require(usermodsDraft.modules[audioReactiveIndex].fields.firstIndex(where: { $0.id == "AudioReactive:config:gain" }))
        usermodsDraft.modules[audioReactiveIndex].fields[enabledIndex].setBoolValue(true)
        usermodsDraft.modules[audioReactiveIndex].fields[gainIndex].value = "72"

        let result = try await service.saveUsermods(
            settingsDraft: settingsDraft,
            usermodsDraft: usermodsDraft,
            for: testDevice()
        )

        #expect(result.savedKeys == ["AudioReactive:config:gain", "AudioReactive:enabled"])
        #expect(result.statusText == "Saved")
        #expect(submittedEntries.isEmpty == false)
    }

    @Test func usermodsInfoReadsDynamicConfigAsReadOnlyRows() async throws {
        let service = makeService { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }

            #expect(request.httpMethod == "GET")
            #expect(url.path == "/json/cfg")
            let json = """
            {
              "um": {
                "Display": {
                  "enabled": true,
                  "pin": 4,
                  "mode": "clock"
                },
                "Sensor": {
                  "threshold": 12
                }
              }
            }
            """
            return (response, Data(json.utf8))
        }

        let info = try await service.fetchUsermodsInfo(for: testDevice())

        #expect(info.modules.map(\.name) == ["Display", "Sensor"])
        #expect(info.modules[0].rows.contains { $0.path == "Display.enabled" && $0.value == "On" })
        #expect(info.modules[0].rows.contains { $0.path == "Display.pin" && $0.value == "4" })
        #expect(info.modules[0].rows.contains { $0.path == "Display.mode" && $0.value == "clock" })
    }

    @Test func dmxOutputDraftUsesWLEDDMXFormAndPreservesFixtureMap() async throws {
        var config: [String: Any] = [
            "dmx": [
                "e131proxy": 0,
                "chan": 3,
                "start": 1,
                "gap": 10,
                "start-led": 0,
                "fixmap": [1, 2, 3, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
            ]
        ]
        var formPost: [String: String] = [:]

        let service = makeService { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }

            if request.httpMethod == "POST", url.path == "/settings/dmx" {
                let body = try #require(MockAdvancedWLEDURLProtocol.requestBodies().last ?? nil)
                formPost = decodedFormValues(from: body)
                #expect(formPost["PU"] == "2")
                #expect(formPost["CN"] == "4")
                #expect(formPost["CS"] == "12")
                #expect(formPost["CG"] == "16")
                #expect(formPost["SL"] == "30")
                #expect(formPost["CH1"] == "1")
                #expect(formPost["CH2"] == "2")
                #expect(formPost["CH3"] == "3")
                #expect(formPost["CH4"] == "5")
                #expect(formPost["CH15"] == "0")

                let preservedFixtureMap = (1...15).map { index in
                    Int(formPost["CH\(index)"] ?? "0") ?? 0
                }
                config["dmx"] = [
                    "e131proxy": Int(formPost["PU"] ?? "0") ?? 0,
                    "chan": Int(formPost["CN"] ?? "3") ?? 3,
                    "start": Int(formPost["CS"] ?? "1") ?? 1,
                    "gap": Int(formPost["CG"] ?? "10") ?? 10,
                    "start-led": Int(formPost["SL"] ?? "0") ?? 0,
                    "fixmap": preservedFixtureMap
                ]
                return (response, Data("DMX settings saved.".utf8))
            }

            if request.httpMethod == "POST" {
                Issue.record("Expected DMX Output category to use /settings/dmx, got \(url.path)")
                throw URLError(.badURL)
            }

            let data = try JSONSerialization.data(withJSONObject: config)
            return (response, data)
        }

        var draft = try await service.fetchDraft(categoryID: "dmx-output", for: testDevice())
        #expect(draft.values["PU"] == WLEDSettingValue.number(0))
        #expect(draft.values["CN"] == WLEDSettingValue.number(3))
        #expect(draft.values["CS"] == WLEDSettingValue.number(1))

        draft.setValue(WLEDSettingValue.number(2), for: "PU")
        draft.setValue(WLEDSettingValue.number(4), for: "CN")
        draft.setValue(WLEDSettingValue.number(12), for: "CS")
        draft.setValue(WLEDSettingValue.number(16), for: "CG")
        draft.setValue(WLEDSettingValue.number(30), for: "SL")

        let result = try await service.saveDraft(draft, for: testDevice())

        #expect(result.savedKeys == ["PU", "CN", "CS", "CG", "SL"])
        #expect(result.statusText == "Saved")
        #expect((config["dmx"] as? [String: Any])?["chan"] as? Int == 4)
        #expect(formPost["CH4"] == "5")
    }

    @Test func syncInterfacesDraftUsesWLEDSyncFormAndPreservesWriteOnlySecrets() async throws {
        var config: [String: Any] = [
            "id": [
                "inv": "Bookshelf"
            ],
            "hw": [
                "baud": 1152,
                "btn": [
                    "mqtt": false
                ]
            ],
            "if": [
                "sync": [
                    "port0": 21324,
                    "port1": 65506,
                    "espnow": false,
                    "recv": [
                        "bri": true,
                        "col": true,
                        "fx": true,
                        "pal": true,
                        "grp": 1,
                        "seg": false,
                        "sb": false
                    ],
                    "send": [
                        "en": false,
                        "dir": true,
                        "btn": true,
                        "va": false,
                        "hue": false,
                        "grp": 1,
                        "ret": 0
                    ]
                ],
                "nodes": [
                    "list": true,
                    "bcast": true
                ],
                "live": [
                    "en": true,
                    "mso": false,
                    "rlm": true,
                    "port": 5568,
                    "mc": false,
                    "dmx": [
                        "uni": 1,
                        "seqskip": false,
                        "e131prio": 0,
                        "addr": 1,
                        "dss": 0,
                        "mode": 4,
                        "inputRxPin": -1,
                        "inputTxPin": -1,
                        "inputEnablePin": -1,
                        "dmxInputPort": 2
                    ],
                    "timeout": 25,
                    "maxbri": false,
                    "no-gc": true,
                    "offset": 0
                ],
                "va": [
                    "alexa": true,
                    "p": 4
                ],
                "mqtt": [
                    "en": false,
                    "broker": "",
                    "port": 1883,
                    "user": "",
                    "pskl": 12,
                    "cid": "WLED-a57aa8",
                    "rtn": false,
                    "topics": [
                        "device": "wled/a57aa8",
                        "group": "wled/all"
                    ]
                ],
                "hue": [
                    "en": false,
                    "id": 1,
                    "iv": 25,
                    "recv": [
                        "on": true,
                        "bri": true,
                        "col": true
                    ],
                    "ip": [192, 168, 0, 0]
                ]
            ]
        ]
        var formPost: [String: String] = [:]

        let service = makeService { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }

            if request.httpMethod == "POST", url.path == "/settings/sync" {
                let body = try #require(MockAdvancedWLEDURLProtocol.requestBodies().last ?? nil)
                formPost = decodedFormValues(from: body)
                #expect(formPost["GS"] == "5")
                #expect(formPost["GR"] == "3")
                #expect(formPost["MS"] == "mqtt.local")
                #expect(formPost["MQPASS"] == "mqttpass123")
                #expect(formPost["HI"] == "3000")
                #expect(formPost["ET"] == "2500")
                #expect(formPost["IDMR"] == "21")
                #expect(formPost["BD"] == "2304")

                var interfaces = config["if"] as? [String: Any] ?? [:]
                var sync = interfaces["sync"] as? [String: Any] ?? [:]
                var recv = sync["recv"] as? [String: Any] ?? [:]
                var send = sync["send"] as? [String: Any] ?? [:]
                recv["grp"] = Int(formPost["GR"] ?? "0") ?? 0
                send["grp"] = Int(formPost["GS"] ?? "0") ?? 0
                sync["recv"] = recv
                sync["send"] = send
                interfaces["sync"] = sync

                var mqtt = interfaces["mqtt"] as? [String: Any] ?? [:]
                mqtt["broker"] = formPost["MS"] ?? ""
                mqtt["pskl"] = formPost["MQPASS"] == "********" ? 12 : (formPost["MQPASS"]?.count ?? 0)
                interfaces["mqtt"] = mqtt

                var hue = interfaces["hue"] as? [String: Any] ?? [:]
                hue["iv"] = (Int(formPost["HI"] ?? "2500") ?? 2500) / 100
                interfaces["hue"] = hue

                var live = interfaces["live"] as? [String: Any] ?? [:]
                var dmx = live["dmx"] as? [String: Any] ?? [:]
                dmx["inputRxPin"] = Int(formPost["IDMR"] ?? "-1") ?? -1
                live["dmx"] = dmx
                interfaces["live"] = live

                config["if"] = interfaces
                var hardware = config["hw"] as? [String: Any] ?? [:]
                hardware["baud"] = Int(formPost["BD"] ?? "1152") ?? 1152
                config["hw"] = hardware
                return (response, Data("Sync settings saved.".utf8))
            }

            if request.httpMethod == "POST" {
                Issue.record("Expected Sync Interfaces to use /settings/sync, got \(url.path)")
                throw URLError(.badURL)
            }

            let data = try JSONSerialization.data(withJSONObject: config)
            return (response, data)
        }

        let device = testDevice()
        var draft = try await service.fetchDraft(categoryID: "sync-interfaces", for: device)
        #expect(draft.values["MS"] == .string(""))
        #expect(draft.values["HI"] == .number(25))
        #expect(draft.secretStates["MQPASS"] == .preserve(configured: true))

        draft.setValue(.number(5), for: "GS")
        draft.setValue(.number(3), for: "GR")
        draft.setValue(.string("mqtt.local"), for: "MS")
        draft.setValue(.number(30), for: "HI")
        draft.setValue(.number(21), for: "IDMR")
        draft.setValue(.number(2304), for: "BD")
        draft.setSecretState(.replace("mqttpass123"), for: "MQPASS")

        let result = try await service.saveDraft(draft, for: device)

        #expect(result.savedKeys == ["GS", "GR", "MS", "HI", "IDMR", "BD", "MQPASS"])
        #expect(formPost["MQCID"] == "WLED-a57aa8")
        #expect((((config["if"] as? [String: Any])?["hue"] as? [String: Any])?["iv"] as? Int) == 30)
        #expect(((((config["if"] as? [String: Any])?["live"] as? [String: Any])?["dmx"] as? [String: Any])?["inputRxPin"] as? Int) == 21)
        #expect((config["hw"] as? [String: Any])?["baud"] as? Int == 2304)
    }

    @Test func categoryDraftSavesOnlyChangedCurrentCategoryFields() async throws {
        var config: [String: Any] = [
            "hw": [
                "led": [
                    "maxpwr": 850,
                    "fps": 42
                ]
            ],
            "light": [
                "scale-bri": 100,
                "gc": [
                    "col": 2.2,
                    "bri": 1,
                    "val": 2.2
                ]
            ]
        ]

        let service = makeService { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }

            if request.httpMethod == "POST" {
                let body = try #require(MockAdvancedWLEDURLProtocol.requestBodies().last ?? nil)
                config = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
                return (response, Data(#"{"success":true}"#.utf8))
            }

            let data = try JSONSerialization.data(withJSONObject: config)
            return (response, data)
        }

        let device = testDevice()
        var draft = try await service.fetchDraft(categoryID: "led-hardware", for: device)
        #expect(draft.values["BF"] == .number(100))

        draft.setValue(.number(88), for: "BF")
        let result = try await service.saveDraft(draft, for: device)

        #expect(result.savedKeys == ["BF"])
        #expect((config["light"] as? [String: Any])?["scale-bri"] as? Int == 88)
        #expect((config["hw"] as? [String: Any])?["led"] != nil)
        #expect(MockAdvancedWLEDURLProtocol.requests().filter { $0.url?.path == "/json/cfg" }.count >= 3)
    }

    @Test func timeMacrosDraftSavesCountdownAndClockFieldsWithoutTouchingMDNS() async throws {
        var config: [String: Any] = [
            "id": [
                "mdns": "aesdetic-lamp"
            ],
            "hw": [
                "btn": [
                    "ins": [
                        [
                            "type": 2,
                            "macros": [11, 12, 13]
                        ]
                    ]
                ]
            ],
            "if": [
                "ntp": [
                    "en": true,
                    "host": "1.wled.pool.ntp.org",
                    "tz": 9,
                    "offset": 0,
                    "ampm": true,
                    "lt": -22.37,
                    "ln": 114.29
                ],
                "va": [
                    "macros": [0, 0]
                ]
            ],
            "ol": [
                "clock": false,
                "cntdwn": false,
                "min": 0,
                "max": 119,
                "o12pix": 0,
                "o5m": false,
                "osec": false,
                "osb": false
            ],
            "timers": [
                "cntdwn": [
                    "goal": [26, 7, 4, 12, 30, 15],
                    "macro": 0
                ],
                "ins": [
                    [
                        "en": 1,
                        "hour": 254,
                        "min": -15,
                        "macro": 10,
                        "dow": 127,
                        "start": ["mon": 1, "day": 1],
                        "end": ["mon": 12, "day": 31]
                    ]
                ]
            ],
            "light": [
                "nl": [
                    "macro": 0
                ]
            ]
        ]

        let service = makeService { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }

            if request.httpMethod == "POST" {
                #expect(url.path == "/settings/time")
                let body = try #require(MockAdvancedWLEDURLProtocol.requestBodies().last ?? nil)
                let form = decodedFormValues(from: body)
                #expect(form["CF"] == "on")
                #expect(form["CM"] == "45")
                #expect(form["LT"] == "-22.36")
                #expect(form["LN"] == "114.28")
                #expect(form["MP0"] == "11")
                #expect(form["ML0"] == "12")
                #expect(form["MD0"] == "13")
                #expect(form["T0"] == "10")
                #expect(form["H0"] == "254")
                #expect(form["N0"] == "-15")
                #expect(form["W0"] == "255")

                var interfaces = config["if"] as? [String: Any] ?? [:]
                var ntp = interfaces["ntp"] as? [String: Any] ?? [:]
                ntp["en"] = form["NT"] == "on"
                ntp["host"] = form["NS"] ?? ""
                ntp["ampm"] = form["CF"] != "on"
                ntp["tz"] = Int(form["TZ"] ?? "0") ?? 0
                ntp["offset"] = Int(form["UO"] ?? "0") ?? 0
                ntp["lt"] = Double(form["LT"] ?? "0") ?? 0
                ntp["ln"] = Double(form["LN"] ?? "0") ?? 0
                interfaces["ntp"] = ntp
                var va = interfaces["va"] as? [String: Any] ?? [:]
                va["macros"] = [
                    Int(form["A0"] ?? "0") ?? 0,
                    Int(form["A1"] ?? "0") ?? 0
                ]
                interfaces["va"] = va
                config["if"] = interfaces

                var overlay = config["ol"] as? [String: Any] ?? [:]
                overlay["clock"] = form["OL"] == "on"
                overlay["cntdwn"] = form["CE"] == "on"
                overlay["min"] = Int(form["O1"] ?? "0") ?? 0
                overlay["max"] = Int(form["O2"] ?? "0") ?? 0
                overlay["o12pix"] = Int(form["OM"] ?? "0") ?? 0
                overlay["o5m"] = form["O5"] == "on"
                overlay["osec"] = form["OS"] == "on"
                overlay["osb"] = form["OB"] == "on"
                config["ol"] = overlay

                var timers = config["timers"] as? [String: Any] ?? [:]
                var countdown = timers["cntdwn"] as? [String: Any] ?? [:]
                countdown["goal"] = [
                    Int(form["CY"] ?? "0") ?? 0,
                    Int(form["CI"] ?? "1") ?? 1,
                    Int(form["CD"] ?? "1") ?? 1,
                    Int(form["CH"] ?? "0") ?? 0,
                    Int(form["CM"] ?? "0") ?? 0,
                    Int(form["CS"] ?? "0") ?? 0
                ]
                countdown["macro"] = Int(form["MC"] ?? "0") ?? 0
                timers["cntdwn"] = countdown
                config["timers"] = timers

                var light = config["light"] as? [String: Any] ?? [:]
                var nightlight = light["nl"] as? [String: Any] ?? [:]
                nightlight["macro"] = Int(form["MN"] ?? "0") ?? 0
                light["nl"] = nightlight
                config["light"] = light
                return (response, Data(#"{"success":true}"#.utf8))
            }

            let data = try JSONSerialization.data(withJSONObject: config)
            return (response, data)
        }

        let device = testDevice()
        var draft = try await service.fetchDraft(categoryID: "time-macros", for: device)
        #expect(draft.values["CF"] == .bool(false))
        #expect(draft.values["CM"] == .number(30))
        #expect(draft.values["O2"] == .number(119))
        #expect(draft.values["LT"] == .number(-22.37))

        draft.setValue(.bool(true), for: "CF")
        draft.setValue(.number(45), for: "CM")
        draft.setValue(.bool(true), for: "CE")
        draft.setValue(.number(120), for: "O2")
        draft.setValue(.number(-22.36), for: "LT")
        draft.setValue(.number(114.28), for: "LN")
        draft.setValue(.number(7), for: "A0")

        let result = try await service.saveDraft(draft, for: device)

        #expect(result.savedKeys == ["A0", "CE", "CF", "CM", "LN", "LT", "O2"])
        #expect((config["id"] as? [String: Any])?["mdns"] as? String == "aesdetic-lamp")
        #expect(((config["if"] as? [String: Any])?["ntp"] as? [String: Any])?["ampm"] as? Bool == false)
        #expect((((config["hw"] as? [String: Any])?["btn"] as? [String: Any])?["ins"] as? [[String: Any]])?.first?["macros"] as? [Int] == [11, 12, 13])
        #expect(((config["if"] as? [String: Any])?["ntp"] as? [String: Any])?["lt"] as? Double == -22.36)
        #expect(((config["if"] as? [String: Any])?["ntp"] as? [String: Any])?["ln"] as? Double == 114.28)
        #expect((config["ol"] as? [String: Any])?["cntdwn"] as? Bool == true)
        #expect((config["ol"] as? [String: Any])?["max"] as? Int == 120)
        let goal = try #require(((config["timers"] as? [String: Any])?["cntdwn"] as? [String: Any])?["goal"] as? [Any])
        #expect(goal[4] as? Int == 45)
        #expect((((config["if"] as? [String: Any])?["va"] as? [String: Any])?["macros"] as? [Any])?[0] as? Int == 7)
    }

    @Test func brightnessLimiterUsesWLEDLEDSettingsFormAndDoesNotSnapBack() async throws {
        var config: [String: Any] = [
            "hw": [
                "led": [
                    "maxpwr": 0,
                    "fps": 42,
                    "ins": []
                ],
                "btn": [
                    "pull": true,
                    "tt": 32,
                    "ins": []
                ],
                "ir": [
                    "pin": -1,
                    "type": 0,
                    "sel": true
                ],
                "relay": [
                    "pin": -1,
                    "rev": true,
                    "odrain": false
                ]
            ],
            "light": [
                "scale-bri": 100,
                "aseg": false,
                "gc": [
                    "col": 2.8,
                    "bri": 1,
                    "val": 2.8
                ],
                "tr": [
                    "dur": 7,
                    "rpc": 5,
                    "hrp": true
                ],
                "nl": [
                    "dur": 60,
                    "tbri": 0,
                    "mode": 0
                ],
                "pal-mode": 0
            ],
            "def": [
                "on": true,
                "bri": 128,
                "ps": 0
            ]
        ]
        var formPosts: [String] = []

        let service = makeService { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }

            if request.httpMethod == "POST", url.path == "/settings/leds" {
                let body = try #require(MockAdvancedWLEDURLProtocol.requestBodies().last ?? nil)
                let form = String(data: body, encoding: .utf8) ?? ""
                formPosts.append(form)
                let maxPower: Int
                if form.contains("ABL=on") {
                    maxPower = form.contains("MA=850") ? 850 : 0
                } else {
                    maxPower = 0
                }
                var hw = config["hw"] as? [String: Any] ?? [:]
                var led = hw["led"] as? [String: Any] ?? [:]
                led["maxpwr"] = maxPower
                hw["led"] = led
                config["hw"] = hw
                return (response, Data("LED settings saved.".utf8))
            }

            if request.httpMethod == "POST" {
                Issue.record("Expected brightness limiter to use /settings/leds fallback, got \(url.path)")
                throw URLError(.badURL)
            }

            let data = try JSONSerialization.data(withJSONObject: config)
            return (response, data)
        }

        let device = testDevice()
        var draft = try await service.fetchDraft(categoryID: "led-hardware", for: device)
        #expect(draft.values["ABL"] == .bool(false))

        draft.setValue(.bool(true), for: "ABL")
        let enableResult = try await service.saveDraft(draft, for: device)

        #expect(enableResult.savedKeys == ["ABL"])
        #expect(formPosts.last?.contains("ABL=on") == true)
        #expect(formPosts.last?.contains("MA=850") == true)
        #expect(((config["hw"] as? [String: Any])?["led"] as? [String: Any])?["maxpwr"] as? Int == 850)

        draft = try await service.fetchDraft(categoryID: "led-hardware", for: device)
        #expect(draft.values["ABL"] == .bool(true))

        draft.setValue(.bool(false), for: "ABL")
        let disableResult = try await service.saveDraft(draft, for: device)

        #expect(disableResult.savedKeys == ["ABL"])
        #expect(formPosts.last?.contains("ABL=on") == false)
        #expect(((config["hw"] as? [String: Any])?["led"] as? [String: Any])?["maxpwr"] as? Int == 0)
    }

    @Test func wifiNetworkDraftUsesWLEDFormAndPreservesWriteOnlySecrets() async throws {
        var config: [String: Any] = [
            "id": [
                "mdns": "wled"
            ],
            "eth": [
                "type": 0
            ],
            "nw": [
                "dns": [8, 8, 4, 4],
                "espnow": false,
                "linked_remote": ["aabbccddeeff"],
                "ins": [
                    [
                        "ssid": "Home WiFi",
                        "pskl": 12,
                        "bssid": "",
                        "ip": [0, 0, 0, 0],
                        "gw": [0, 0, 0, 0],
                        "sn": [255, 255, 255, 0]
                    ]
                ]
            ],
            "ap": [
                "ssid": "WLED-AP",
                "pskl": 8,
                "chan": 6,
                "hide": false,
                "behav": 1,
                "ip": [4, 3, 2, 1]
            ],
            "wifi": [
                "sleep": true,
                "phy": false,
                "txpwr": 78
            ]
        ]
        var formPost: [String: String] = [:]
        var wifiFormPostCount = 0

        let service = makeService { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }

            if request.httpMethod == "POST", url.path == "/settings/wifi" {
                let body = try #require(MockAdvancedWLEDURLProtocol.requestBodies().last ?? nil)
                let form = decodedFormValues(from: body)
                formPost = form
                wifiFormPostCount += 1

                #expect(form["CS0"] == "Home WiFi")
                #expect(form["PW0"] == "********")
                if wifiFormPostCount == 1 {
                    #expect(form["AP"] == "********")
                } else {
                    #expect(form["AP"] == "newpass123")
                }
                #expect(form["RM0"] == "aabbccddeeff")

                config["id"] = ["mdns": form["CM"] ?? ""]
                config["eth"] = ["type": Int(form["ETH"] ?? "0") ?? 0]
                let dns: [Int] = [
                    Int(form["D0"] ?? "0") ?? 0,
                    Int(form["D1"] ?? "0") ?? 0,
                    Int(form["D2"] ?? "0") ?? 0,
                    Int(form["D3"] ?? "0") ?? 0
                ]
                let ip: [Int] = [
                    Int(form["IP00"] ?? "0") ?? 0,
                    Int(form["IP01"] ?? "0") ?? 0,
                    Int(form["IP02"] ?? "0") ?? 0,
                    Int(form["IP03"] ?? "0") ?? 0
                ]
                let gateway: [Int] = [
                    Int(form["GW00"] ?? "0") ?? 0,
                    Int(form["GW01"] ?? "0") ?? 0,
                    Int(form["GW02"] ?? "0") ?? 0,
                    Int(form["GW03"] ?? "0") ?? 0
                ]
                let subnet: [Int] = [
                    Int(form["SN00"] ?? "255") ?? 255,
                    Int(form["SN01"] ?? "255") ?? 255,
                    Int(form["SN02"] ?? "255") ?? 255,
                    Int(form["SN03"] ?? "0") ?? 0
                ]
                let network: [String: Any] = [
                    "ssid": form["CS0"] ?? "",
                    "pskl": 12,
                    "bssid": form["BS0"] ?? "",
                    "ip": ip,
                    "gw": gateway,
                    "sn": subnet
                ]
                let nw: [String: Any] = [
                    "dns": dns,
                    "espnow": form["RE"] == "on",
                    "linked_remote": ["aabbccddeeff"],
                    "ins": [network]
                ]
                config["nw"] = nw
                config["ap"] = [
                    "ssid": form["AS"] ?? "",
                    "pskl": form["AP"] == "********" ? 8 : (form["AP"]?.count ?? 0),
                    "chan": Int(form["AC"] ?? "1") ?? 1,
                    "hide": form["AH"] == "on",
                    "behav": Int(form["AB"] ?? "0") ?? 0,
                    "ip": [4, 3, 2, 1]
                ]
                config["wifi"] = [
                    "sleep": form["WS"] != "on",
                    "phy": form["FG"] == "on",
                    "txpwr": Int(form["TX"] ?? "78") ?? 78
                ]
                return (response, Data("WiFi settings saved.".utf8))
            }

            if request.httpMethod == "POST" {
                Issue.record("Expected WiFi category to use /settings/wifi fallback, got \(url.path)")
                throw URLError(.badURL)
            }

            let data = try JSONSerialization.data(withJSONObject: config)
            return (response, data)
        }

        let device = testDevice()
        var draft = try await service.fetchDraft(categoryID: "wifi-network", for: device)
        #expect(draft.values["CM"] == WLEDSettingValue.string("wled"))
        #expect(draft.values["WS"] == WLEDSettingValue.bool(false))
        #expect(draft.secretStates["AP"] == WLEDSecretDraftState.preserve(configured: true))

        draft.setValue(WLEDSettingValue.string("http://aesdetic.test.local/"), for: "CM")
        draft.setValue(WLEDSettingValue.number(11), for: "AC")
        draft.setValue(WLEDSettingValue.string("2"), for: "AB")
        draft.setValue(WLEDSettingValue.bool(true), for: "AH")
        draft.setValue(WLEDSettingValue.bool(true), for: "WS")
        draft.setValue(WLEDSettingValue.bool(true), for: "FG")
        draft.setValue(WLEDSettingValue.string("68"), for: "TX")
        draft.setValue(WLEDSettingValue.bool(true), for: "RE")

        let result = try await service.saveDraft(draft, for: device)

        #expect(result.savedKeys == ["CM", "AC", "AB", "AH", "WS", "FG", "TX", "RE"])
        #expect(result.statusText == "Reconnect Required")
        #expect(formPost["CM"] == "aesdetic.test")
        #expect(formPost["AC"] == "11")
        #expect(formPost["AB"] == "2")
        #expect(formPost["AH"] == "on")
        #expect(formPost["WS"] == "on")
        #expect(formPost["FG"] == "on")
        #expect(formPost["TX"] == "68")
        #expect(formPost["RE"] == "on")

        draft = try await service.fetchDraft(categoryID: "wifi-network", for: device)
        #expect(draft.values["CM"] == WLEDSettingValue.string("aesdetic.test"))
        #expect(draft.values["AC"] == WLEDSettingValue.number(11))
        #expect(draft.values["AB"] == WLEDSettingValue.string("2"))
        #expect(draft.values["AH"] == WLEDSettingValue.bool(true))
        #expect(draft.values["WS"] == WLEDSettingValue.bool(true))
        #expect(draft.values["FG"] == WLEDSettingValue.bool(true))
        #expect(draft.values["TX"] == WLEDSettingValue.string("68"))
        #expect(draft.values["RE"] == WLEDSettingValue.bool(true))

        draft.setSecretState(.replace("newpass123"), for: "AP")
        let secretResult = try await service.saveDraft(draft, for: device)

        #expect(secretResult.savedKeys == ["AP"])
        #expect(formPost["AP"] == "newpass123")

        draft.setSecretState(.replace("short"), for: "AP")
        #expect(draft.validationErrors()["AP"] == "AP password (leave empty for open) must be empty or 8-63 characters.")
    }

    @Test func ledOutputDraftSavesNativeBusConfiguration() async throws {
        var config: [String: Any] = [
            "hw": [
                "com": [
                    [
                        "start": 12,
                        "len": 8,
                        "order": 49
                    ]
                ],
                "led": [
                    "total": 120,
                    "maxpwr": 850,
                    "ins": [
                        [
                            "type": 22,
                            "pin": [16],
                            "len": 120,
                            "start": 0,
                            "skip": 0,
                            "rev": false,
                            "ref": false,
                            "order": 32,
                            "rgbwm": 0,
                            "freq": 0,
                            "ledma": 55,
                            "maxpwr": 850,
                            "drv": 0,
                            "per": false
                        ]
                    ]
                ]
            ],
            "light": [
                "scale-bri": 100
            ]
        ]

        let service = makeService { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }

            if request.httpMethod == "POST" {
                let body = try #require(MockAdvancedWLEDURLProtocol.requestBodies().last ?? nil)
                config = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
                return (response, Data(#"{"success":true}"#.utf8))
            }

            let data = try JSONSerialization.data(withJSONObject: config)
            return (response, data)
        }

        let device = testDevice()
        var draft = try await service.fetchLEDOutputDraft(for: device)
        #expect(draft.outputs.count == 1)
        #expect(draft.outputs[0].pins == "16")
        #expect(draft.outputs[0].colorOrder == 0)
        #expect(draft.outputs[0].whiteChannelSwap == 2)
        #expect(draft.colorOverrides.count == 1)
        #expect(draft.colorOverrides[0].start == 12)
        #expect(draft.colorOverrides[0].length == 8)
        #expect(draft.colorOverrides[0].colorOrder == 1)
        #expect(draft.colorOverrides[0].whiteChannelSwap == 3)
        #expect(draft.diagnostics.totalLEDs == 120)
        #expect(draft.diagnostics.estimatedMemoryUsedBytes == 2032)

        draft.outputs[0].pins = "16, 17"
        draft.outputs[0].length = 96
        draft.outputs[0].reverse = true
        draft.outputs[0].colorOrder = 1
        draft.outputs[0].whiteChannelSwap = 2
        draft.outputs[0].perOutputLimiter = true
        draft.colorOverrides[0].start = 24
        draft.colorOverrides[0].length = 12
        draft.colorOverrides[0].colorOrder = 4
        draft.colorOverrides[0].whiteChannelSwap = 1
        draft.addOutput()
        draft.outputs[1].pins = "18"
        draft.outputs[1].length = 24
        draft.outputs[1].start = 96
        draft.outputs[1].whiteChannelSwap = 0
        draft.outputs[1].maxPowerMilliamps = 500

        let result = try await service.saveLEDOutputDraft(draft, for: device)

        #expect(result.savedKeys == ["LEDOUT"])
        let led = try #require((config["hw"] as? [String: Any])?["led"] as? [String: Any])
        #expect(led["total"] as? Int == 120)
        let outputs = try #require(led["ins"] as? [[String: Any]])
        #expect(outputs.count == 2)
        #expect(outputs[0]["pin"] as? [Int] == [16, 17])
        #expect(outputs[0]["len"] as? Int == 96)
        #expect(outputs[0]["rev"] as? Bool == true)
        #expect(outputs[0]["order"] as? Int == 33)
        #expect(outputs[0]["per"] == nil)
        #expect(outputs[0]["maxpwr"] as? Int == 850)
        #expect(outputs[1]["pin"] as? [Int] == [18])
        #expect(outputs[1]["start"] as? Int == 96)
        #expect(outputs[1]["maxpwr"] as? Int == 0)
        let colorOverrides = try #require((config["hw"] as? [String: Any])?["com"] as? [[String: Any]])
        #expect(colorOverrides.count == 1)
        #expect(colorOverrides[0]["start"] as? Int == 24)
        #expect(colorOverrides[0]["len"] as? Int == 12)
        #expect(colorOverrides[0]["order"] as? Int == 20)
    }

    @Test func ledOutputSaveRetriesUntilWLEDReflectsDelayedReinit() async throws {
        let originalConfig: [String: Any] = [
            "hw": [
                "com": [],
                "led": [
                    "total": 120,
                    "ins": [
                        [
                            "type": 22,
                            "pin": [16],
                            "len": 120,
                            "start": 0,
                            "skip": 0,
                            "rev": false,
                            "ref": false,
                            "order": 0,
                            "rgbwm": 0,
                            "freq": 0,
                            "ledma": 55,
                            "maxpwr": 0,
                            "drv": 0
                        ]
                    ]
                ]
            ]
        ]
        var config = originalConfig
        var getCountAfterPost = 0
        var didPost = false

        let service = makeService { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }

            if request.httpMethod == "POST" {
                let body = try #require(MockAdvancedWLEDURLProtocol.requestBodies().last ?? nil)
                config = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
                didPost = true
                return (response, Data(#"{"success":true}"#.utf8))
            }

            if didPost {
                getCountAfterPost += 1
            }
            let data = try JSONSerialization.data(withJSONObject: didPost && getCountAfterPost == 1 ? originalConfig : config)
            return (response, data)
        }

        let device = testDevice()
        var draft = try await service.fetchLEDOutputDraft(for: device)
        draft.outputs[0].length = 60

        let result = try await service.saveLEDOutputDraft(draft, for: device)

        #expect(result.savedKeys == ["LEDOUT"])
        #expect(getCountAfterPost >= 2)
    }

    @Test func ledOutputSaveClearsColorOverridesWithWLEDSettingsFormFallback() async throws {
        var config: [String: Any] = [
            "hw": [
                "com": [
                    [
                        "start": 10,
                        "len": 4,
                        "order": 1
                    ]
                ],
                "led": [
                    "maxpwr": 850,
                    "fps": 42,
                    "total": 120,
                    "ins": [
                        [
                            "type": 22,
                            "pin": [16],
                            "len": 120,
                            "start": 0,
                            "skip": 0,
                            "rev": false,
                            "ref": false,
                            "order": 0,
                            "rgbwm": 0,
                            "freq": 0,
                            "ledma": 55,
                            "maxpwr": 0,
                            "drv": 0
                        ]
                    ]
                ],
                "btn": [
                    "pull": true,
                    "tt": 32,
                    "ins": []
                ],
                "ir": [
                    "pin": -1,
                    "type": 0,
                    "sel": true
                ],
                "relay": [
                    "pin": -1,
                    "rev": true,
                    "odrain": false
                ]
            ],
            "light": [
                "scale-bri": 100,
                "aseg": false,
                "gc": [
                    "col": 2.8,
                    "bri": 1,
                    "val": 2.8
                ],
                "tr": [
                    "dur": 7,
                    "rpc": 5,
                    "hrp": true
                ],
                "nl": [
                    "dur": 60,
                    "tbri": 0,
                    "mode": 0
                ],
                "pal-mode": 0
            ],
            "def": [
                "on": true,
                "bri": 128,
                "ps": 0
            ]
        ]
        var didUseFormFallback = false

        let service = makeService { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }

            if request.httpMethod == "POST", url.path == "/settings/leds" {
                let body = try #require(MockAdvancedWLEDURLProtocol.requestBodies().last ?? nil)
                let form = String(data: body, encoding: .utf8) ?? ""
                #expect(form.contains("L00=16"))
                #expect(form.contains("LC0=120"))
                #expect(form.contains("BF=100"))
                #expect(!form.contains("XS0="))
                var hw = config["hw"] as? [String: Any] ?? [:]
                hw["com"] = []
                config["hw"] = hw
                didUseFormFallback = true
                return (response, Data("LED settings saved.".utf8))
            }

            if request.httpMethod == "POST" {
                Issue.record("Expected color override clear to use /settings/leds fallback, got \(url.path)")
                throw URLError(.badURL)
            }

            let data = try JSONSerialization.data(withJSONObject: config)
            return (response, data)
        }

        let device = testDevice()
        var draft = try await service.fetchLEDOutputDraft(for: device)
        draft.colorOverrides.removeAll()

        let result = try await service.saveLEDOutputDraft(draft, for: device)

        #expect(result.savedKeys == ["LEDOUT"])
        #expect(didUseFormFallback)
    }

    @Test func ledOutputDraftMutatesDynamicRowsByStableIDAfterRemoval() throws {
        var draft = makeLEDOutputDraft(
            outputs: [
                makeLEDOutput(pins: "16", length: 60, start: 0),
                makeLEDOutput(pins: "17", length: 60, start: 60)
            ],
            colorOverrides: [
                WLEDColorOrderOverride(start: 0, length: 10, colorOrder: 0, whiteChannelSwap: 0),
                WLEDColorOrderOverride(start: 10, length: 10, colorOrder: 1, whiteChannelSwap: 0)
            ]
        )

        let remainingOutputID = draft.outputs[1].id
        var editedOutput = draft.outputs[1]
        editedOutput.length = 72
        draft.removeOutput(at: 0)
        draft.updateOutput(id: remainingOutputID, with: editedOutput)

        #expect(draft.outputs.count == 1)
        #expect(draft.outputs[0].pins == "17")
        #expect(draft.outputs[0].length == 72)

        let removedOverrideID = draft.colorOverrides[0].id
        let remainingOverrideID = draft.colorOverrides[1].id
        var editedOverride = draft.colorOverrides[1]
        editedOverride.length = 24
        draft.removeColorOverride(at: 0)
        draft.updateColorOverride(id: removedOverrideID, with: editedOverride)
        draft.updateColorOverride(id: remainingOverrideID, with: editedOverride)

        #expect(draft.colorOverrides.count == 1)
        #expect(draft.colorOverrides[0].start == 10)
        #expect(draft.colorOverrides[0].length == 24)
    }

    @Test func ledOutputSaveDeduplicatesExactColorOverrides() async throws {
        var config: [String: Any] = [
            "hw": [
                "com": [
                    [
                        "start": 10,
                        "len": 4,
                        "order": 1
                    ],
                    [
                        "start": 10,
                        "len": 4,
                        "order": 1
                    ]
                ],
                "led": [
                    "total": 120,
                    "ins": [
                        [
                            "type": 22,
                            "pin": [16],
                            "len": 120,
                            "start": 0,
                            "skip": 0,
                            "rev": false,
                            "ref": false,
                            "order": 0,
                            "rgbwm": 0,
                            "freq": 0,
                            "ledma": 55,
                            "maxpwr": 0,
                            "drv": 0
                        ]
                    ]
                ]
            ]
        ]

        let service = makeService { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }

            if request.httpMethod == "POST" {
                #expect(url.path == "/json/cfg")
                let body = try #require(MockAdvancedWLEDURLProtocol.requestBodies().last ?? nil)
                config = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
                let colorOverrides = try #require((config["hw"] as? [String: Any])?["com"] as? [[String: Any]])
                #expect(colorOverrides.count == 1)
                return (response, Data(#"{"success":true}"#.utf8))
            }

            let data = try JSONSerialization.data(withJSONObject: config)
            return (response, data)
        }

        let device = testDevice()
        var draft = try await service.fetchLEDOutputDraft(for: device)
        #expect(draft.colorOverrides.count == 1)
        draft.colorOverrides.append(draft.colorOverrides[0])

        let result = try await service.saveLEDOutputDraft(draft, for: device)

        #expect(result.savedKeys == ["LEDOUT"])
    }

    @Test func pinInfoReadsLivePinsAsReadOnlyRows() async throws {
        let service = makeService { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }

            #expect(request.httpMethod == "GET")

            if url.path == "/settings/s.js" {
                return (response, Data("function GetV(){var d=document;d.touch=[0,27,32,33];d.ro_gpio=[34,35,36,37,38,39];d.adc=[32,33,34,35,36,37,38,39];}".utf8))
            }

            #expect(url.path == "/json/pins")

            let json = """
            {
              "pins": [
                {"p":16,"c":0,"a":true,"o":130,"n":"LED Digital"},
                {"p":0,"c":8,"a":true,"o":133,"n":"Button","t":2,"s":1},
                {"p":34,"c":34,"a":false}
              ]
            }
            """
            return (response, Data(json.utf8))
        }

        let info = try await service.fetchPinInfo(for: testDevice())

        #expect(info.pins.map(\.gpio) == [0, 16, 34])
        #expect(info.allocatedCount == 2)
        #expect(info.availableCount == 1)
        #expect(info.pins[0].displayOwner == "Button")
        #expect(info.pins[0].stateText == "On")
        #expect(info.pins[0].noteText == "Touch, Flash Boot")
        #expect(info.pins[1].displayOwner == "LED Digital")
        #expect(info.pins[2].displayOwner == "Available")
        #expect(info.pins[2].noteText == "Input Only, Analog")
    }

    @Test func matrixInfoReadsOneDimensionalStripAsReadOnly() async throws {
        let service = makeService { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }

            if url.path == "/settings/s.js" {
                return (response, Data("function GetV(){var d=document;d.Sf.SOMP.value=0;maxPanels=18;resetPanels();}".utf8))
            }
            if url.path == "/json/info" {
                return (response, Data(#"{"leds":{"count":120}}"#.utf8))
            }
            #expect(url.path == "/json/cfg")
            return (response, Data(#"{"hw":{"led":{"total":120,"ins":[]}}}"#.utf8))
        }

        let info = try await service.fetchMatrixInfo(for: testDevice())

        #expect(info.mode == .strip)
        #expect(info.maxPanels == 18)
        #expect(info.totalLEDs == 120)
        #expect(info.dimensionsText == "Not active")
        #expect(info.panels.isEmpty)
    }

    @Test func matrixInfoReadsPanelLayoutFromConfig() async throws {
        let service = makeService { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }

            if url.path == "/settings/s.js" {
                return (response, Data("function GetV(){var d=document;d.Sf.SOMP.value=1;maxPanels=64;}".utf8))
            }
            if url.path == "/json/info" {
                return (response, Data(#"{"leds":{"count":128,"matrix":{"w":16,"h":8}}}"#.utf8))
            }
            #expect(url.path == "/json/cfg")
            let json = """
            {
              "hw": {
                "led": {
                  "total": 128,
                  "matrix": {
                    "mpc": 2,
                    "panels": [
                      {"b":false,"r":false,"v":false,"s":true,"x":0,"y":0,"w":8,"h":8},
                      {"b":true,"r":true,"v":true,"s":false,"x":8,"y":0,"w":8,"h":8}
                    ]
                  }
                }
              }
            }
            """
            return (response, Data(json.utf8))
        }

        let info = try await service.fetchMatrixInfo(for: testDevice())

        #expect(info.mode == .matrix)
        #expect(info.maxPanels == 64)
        #expect(info.totalLEDs == 128)
        #expect(info.dimensionsText == "16 x 8 = 128")
        #expect(info.panelCountText == "2")
        #expect(info.panels[0].firstLEDText == "Top Left")
        #expect(info.panels[0].layoutText == "Serpentine")
        #expect(info.panels[1].firstLEDText == "Bottom Right")
        #expect(info.panels[1].orientationText == "Vertical")
    }

    @Test @MainActor func customerBehaviorLoadPreservesCustomFirmwareValues() async throws {
        let config: [String: Any] = [
            "hw": [
                "led": ["maxpwr": 0, "fps": 42, "ins": []],
                "btn": ["pull": true, "tt": 32, "ins": []],
                "ir": ["pin": -1, "type": 0, "sel": true],
                "relay": ["pin": -1, "rev": true, "odrain": false]
            ],
            "light": [
                "scale-bri": 140,
                "tr": ["dur": 9, "rpc": 5, "hrp": true],
                "gc": ["col": 2.8, "bri": 1, "val": 2.8],
                "nl": ["dur": 60, "tbri": 0, "mode": 0],
                "pal-mode": 0
            ],
            "def": ["on": false, "bri": 128, "ps": 0]
        ]

        let service = makeService { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            #expect(request.httpMethod == "GET")
            #expect(url.path == "/json/cfg")
            return (response, try JSONSerialization.data(withJSONObject: config))
        }

        let store = DeviceBehaviorSettingsStore(device: testDevice(), service: service)
        await store.load()

        #expect(store.powerOnAfterRestart == false)
        #expect(store.maximumBrightness == 140)
        #expect(store.hasCustomBrightness)
        #expect(store.transitionMilliseconds == 900)
        #expect(store.selectedTransition == nil)
        #expect(store.status == .idle)
    }

    private func makeService(handler: @escaping MockAdvancedWLEDURLProtocol.Handler) -> WLEDAdvancedSettingsService {
        MockAdvancedWLEDURLProtocol.reset(handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockAdvancedWLEDURLProtocol.self]
        return WLEDAdvancedSettingsService(urlSession: URLSession(configuration: configuration))
    }

    private func decodedFormValues(from data: Data) -> [String: String] {
        decodedFormEntries(from: data).reduce(into: [String: String]()) { result, pair in
            result[pair.0] = pair.1
        }
    }

    private func decodedFormEntries(from data: Data) -> [(String, String)] {
        let raw = String(data: data, encoding: .utf8) ?? ""
        return raw.split(separator: "&").compactMap { pair in
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard let key = parts.first else { return nil }
            let value = parts.indices.contains(1) ? parts[1] : ""
            return (decodeFormComponent(key), decodeFormComponent(value))
        }
    }

    private func decodeFormComponent(_ value: String) -> String {
        value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? value
    }

    private func makeLEDOutputDraft(
        outputs: [WLEDLEDOutput],
        colorOverrides: [WLEDColorOrderOverride]
    ) -> WLEDLEDOutputDraft {
        WLEDLEDOutputDraft(
            originalOutputs: outputs,
            originalColorOverrides: colorOverrides,
            diagnostics: WLEDLEDDiagnostics(
                totalLEDs: outputs.reduce(0) { $0 + $1.length },
                brightestWhiteAmps: nil,
                typicalEffectsAmps: nil,
                estimatedMemoryUsedBytes: nil,
                estimatedMemoryAvailableBytes: nil,
                hardwareChannelsSummary: nil
            ),
            outputs: outputs,
            colorOverrides: colorOverrides
        )
    }

    private func makeLEDOutput(pins: String, length: Int, start: Int) -> WLEDLEDOutput {
        WLEDLEDOutput(
            type: 22,
            pins: pins,
            length: length,
            start: start,
            skip: 0,
            reverse: false,
            refreshWhenOff: false,
            colorOrder: 0,
            whiteChannelSwap: 0,
            autoWhiteMode: 0,
            frequency: 0,
            currentMilliamps: 55,
            maxPowerMilliamps: 0,
            driverType: 0,
            perOutputLimiter: false
        )
    }

    private func testDevice() -> WLEDDevice {
        WLEDDevice(
            id: "test-device",
            name: "Test Device",
            ipAddress: "192.168.1.100",
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
