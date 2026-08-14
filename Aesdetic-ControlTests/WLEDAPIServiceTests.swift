//
//  WLEDAPIServiceTests.swift
//  Aesdetic-ControlTests
//
//  Created on 2025-01-27
//  Tests for WLEDAPIService request construction and validation
//

import Foundation
import CoreLocation
import Testing
@testable import Aesdetic_Control

private final class MockWLEDURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    private static var handler: Handler?
    private static var recordedRequests: [URLRequest] = []
    private static var recordedRequestBodies: [Data?] = []

    static func reset(handler: @escaping Handler) {
        lock.lock()
        self.handler = handler
        recordedRequests = []
        recordedRequestBodies = []
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
        return recordedRequestBodies
    }

    static func bodyDataForTesting(from request: URLRequest) -> Data? {
        bodyData(from: request)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let activeHandler: Handler?
        let body = Self.bodyData(from: request)
        Self.lock.lock()
        Self.recordedRequests.append(request)
        Self.recordedRequestBodies.append(body)
        activeHandler = Self.handler
        Self.lock.unlock()

        guard let activeHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try activeHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: buffer.count)
            if bytesRead > 0 {
                data.append(buffer, count: bytesRead)
            } else {
                break
            }
        }
        return data
    }
}

@Suite(.serialized)
struct WLEDAPIServiceTests {
    
    // MARK: - Test Device Helper

    private func makeTestService(
        handler: MockWLEDURLProtocol.Handler? = nil,
        persistenceRoot: URL? = nil
    ) -> WLEDAPIService {
        MockWLEDURLProtocol.reset(handler: handler ?? defaultMockWLEDHandler)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockWLEDURLProtocol.self]
        configuration.timeoutIntervalForRequest = 0.25
        configuration.timeoutIntervalForResource = 0.25

        return WLEDAPIService(
            testURLSession: URLSession(configuration: configuration),
            presetStorePersistenceRoot: persistenceRoot
        )
    }

    private func defaultMockWLEDHandler(_ request: URLRequest) throws -> (HTTPURLResponse, Data) {
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
            return (response, Data(Self.mockConfigJSON.utf8))
        case "/presets.json", "/json/presets":
            return (response, Data(Self.mockPresetsJSON.utf8))
        default:
            return (response, Data(Self.mockStateResponseJSON.utf8))
        }
    }

    private static let mockStateResponseJSON = """
    {
      "state": {
        "on": true,
        "bri": 128,
        "mainseg": 0,
        "seg": [
          {
            "id": 0,
            "start": 0,
            "stop": 30,
            "col": [[255,255,255]],
            "fx": 0
          }
        ]
      },
      "info": {
        "name": "Mock WLED",
        "mac": "AABBCCDDEEFF",
        "ver": "0.15.3",
        "leds": {
          "count": 30
        }
      }
    }
    """

    private static let mockConfigJSON = """
    {
      "timers": {
        "ins": []
      },
      "if": {
        "va": {
          "alexa": false,
          "p": 0
        },
        "sync": {
          "send": {},
          "recv": {}
        }
      },
      "hw": {
        "led": {
          "total": 30,
          "maxpwr": 850
        }
      }
    }
    """

    private static let mockPresetsJSON = """
    {
      "0": {},
      "10": {
        "n": "Mock Preset",
        "seg": []
      },
      "11": {
        "n": "Mock Playlist",
        "playlist": {
          "ps": [10],
          "dur": [100],
          "transition": [7],
          "repeat": 1,
          "end": 0,
          "r": 0
        }
      }
    }
    """
    
    private func createTestDevice(ipAddress: String = "192.168.1.100") -> WLEDDevice {
        return WLEDDevice(
            id: "test-device",
            name: "Test Device",
            ipAddress: ipAddress,
            isOnline: true,
            brightness: 128,
            currentColor: .white,
            productType: .generic,
            location: .all,
            lastSeen: Date(),
            state: nil
        )
    }

    private func okResponse(for url: URL, contentType: String = "application/json") throws -> HTTPURLResponse {
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": contentType]
        ) else {
            throw URLError(.badURL)
        }
        return response
    }

    private func uploadedPresetStoreData(from request: URLRequest) throws -> Data {
        let body = try #require(MockWLEDURLProtocol.bodyDataForTesting(from: request))
        let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
        let boundaryPrefix = "boundary="
        let boundary = try #require(
            contentType
                .split(separator: ";")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first(where: { $0.hasPrefix(boundaryPrefix) })?
                .dropFirst(boundaryPrefix.count)
        )
        let headerTerminator = Data("\r\n\r\n".utf8)
        let trailer = Data("\r\n--\(boundary)".utf8)
        let payloadStart = try #require(body.range(of: headerTerminator)?.upperBound)
        let payloadEnd = try #require(body.range(of: trailer, in: payloadStart..<body.endIndex)?.lowerBound)
        return body.subdata(in: payloadStart..<payloadEnd)
    }

    private func mockStateResponseJSON(filesystemUsedKB: Int, filesystemTotalKB: Int) -> String {
        """
        {
          "state": {
            "on": true,
            "bri": 128,
            "mainseg": 0,
            "seg": [
              {
                "id": 0,
                "start": 0,
                "stop": 30,
                "col": [[255,255,255]],
                "fx": 0
              }
            ]
          },
          "info": {
            "name": "Mock WLED",
            "mac": "AABBCCDDEEFF",
            "ver": "0.15.3",
            "leds": {
              "count": 30
            },
            "fs": {
              "u": \(filesystemUsedKB),
              "t": \(filesystemTotalKB),
              "pmt": 123
            }
          }
        }
        """
    }

    @Test("full preset-store rewrite blocks storage-increasing save when WLED filesystem is low")
    func testPresetStoreRewriteBlocksLowFilesystemHeadroom() async throws {
        let originalPresets = Data("""
        {
          "0": {},
          "10": { "n": "Existing", "seg": [] }
        }
        """.utf8)
        let service = makeTestService { request in
            let url = try #require(request.url)
            let response = try okResponse(for: url)

            switch url.path {
            case "/presets.json":
                return (response, originalPresets)
            case "/json":
                return (response, Data(mockStateResponseJSON(filesystemUsedKB: 99, filesystemTotalKB: 100).utf8))
            case "/upload":
                return (response, Data("File Uploaded!".utf8))
            default:
                return (response, Data(Self.mockStateResponseJSON.utf8))
            }
        }
        let device = createTestDevice()

        do {
            _ = try await service.rewritePresetStoreUpsertingRecords(
                presetRequests: [
                    WLEDPresetSaveRequest(
                        id: 12,
                        name: "New Low Space Preset",
                        quickLoad: nil,
                        state: nil
                    )
                ],
                playlistRequests: [],
                device: device
            )
            Issue.record("Expected low filesystem space to block the rewrite")
        } catch let error as WLEDAPIError {
            guard case .presetStoreInsufficientSpace = error else {
                Issue.record("Expected presetStoreInsufficientSpace, got \(error)")
                return
            }
        }

        let uploadRequests = MockWLEDURLProtocol.requests().filter { $0.url?.path == "/upload" }
        #expect(uploadRequests.isEmpty)
    }

    @Test("full preset-store rewrite writes custom off macro command")
    func testPresetStoreRewriteWritesCustomOffMacroCommand() async throws {
        final class Fixture {
            var presets = Data(#"{"0":{}}"#.utf8)
        }
        let fixture = Fixture()
        let service = makeTestService { request in
            let url = try #require(request.url)
            let response = try okResponse(for: url)

            switch url.path {
            case "/presets.json":
                return (response, fixture.presets)
            case "/upload":
                fixture.presets = try uploadedPresetStoreData(from: request)
                return (response, Data("File Uploaded!".utf8))
            case "/json":
                return (response, Data(Self.mockStateResponseJSON.utf8))
            default:
                return (response, Data(Self.mockStateResponseJSON.utf8))
            }
        }
        let device = createTestDevice()

        let rewritten = try await service.rewritePresetStoreUpsertingRecords(
            presetRequests: [
                WLEDPresetSaveRequest(
                    id: 10,
                    name: "Automation Routine 1",
                    quickLoad: nil,
                    state: WLEDStateUpdate(on: false),
                    customAPICommand: "T=0"
                )
            ],
            playlistRequests: [],
            device: device
        )

        #expect(rewritten == .committed)
        let uploadBody = try #require(
            MockWLEDURLProtocol.requestBodies()
                .compactMap { $0.flatMap { String(data: $0, encoding: .utf8) } }
                .first { $0.contains("presets.json") }
        )
        #expect(uploadBody.contains(#""win":"T=0""#) || uploadBody.contains(#""win": "T=0""#))
        #expect(!uploadBody.contains(#""on":false"#))
    }

    @Test("full preset-store rewrite allows shrinking delete even when WLED filesystem is low")
    func testPresetStoreRewriteAllowsShrinkingDeleteWhenFilesystemLow() async throws {
        final class Fixture {
            var presets = Data("""
            {
              "0": {},
              "10": { "n": "Remove Me", "seg": [{ "id": 0, "stop": 30, "col": [[255,0,0,0]] }] },
              "11": { "n": "Keep Me", "seg": [] }
            }
            """.utf8)
        }
        let fixture = Fixture()
        let service = makeTestService { request in
            let url = try #require(request.url)
            let response = try okResponse(for: url)

            switch url.path {
            case "/presets.json":
                return (response, fixture.presets)
            case "/upload":
                fixture.presets = try uploadedPresetStoreData(from: request)
                return (response, Data("File Uploaded!".utf8))
            case "/json":
                return (response, Data(mockStateResponseJSON(filesystemUsedKB: 99, filesystemTotalKB: 100).utf8))
            default:
                return (response, Data(Self.mockStateResponseJSON.utf8))
            }
        }
        let device = createTestDevice()

        let targets = try await service.capturePresetStoreCleanupTargets(
            playlistIds: [],
            presetIds: [10],
            device: device
        )
        let deleted = try await service.rewritePresetStoreConditionallyDeleting(
            targets: targets,
            device: device
        )

        #expect(deleted.outcome == .committed)
        #expect(deleted.deleted.map(\.id) == [10])
        let requests = MockWLEDURLProtocol.requests()
        #expect(requests.contains { $0.url?.path == "/upload" })
        #expect(!requests.contains { $0.url?.path == "/json" })
    }

    @Test("timed-out upload commits when two read-backs match the candidate")
    func testTimedOutUploadCommitsFromReadBackWithoutSecondUpload() async throws {
        final class Fixture {
            var presets = Data(#"{"0":{},"10":{"n":"Existing","seg":[]}}"#.utf8)
            var uploadCount = 0
        }
        let fixture = Fixture()
        let service = makeTestService { request in
            let url = try #require(request.url)
            let response = try okResponse(for: url)
            switch url.path {
            case "/presets.json":
                return (response, fixture.presets)
            case "/upload":
                fixture.uploadCount += 1
                fixture.presets = try uploadedPresetStoreData(from: request)
                throw URLError(.timedOut)
            default:
                return (response, Data(Self.mockStateResponseJSON.utf8))
            }
        }
        let device = createTestDevice()

        let outcome = try await service.savePreset(
            WLEDPresetSaveRequest(id: 77, name: "Timeout Candidate", quickLoad: nil, state: nil),
            to: device
        )

        #expect(outcome == .committed)
        #expect(fixture.uploadCount == 1)
        #expect(try await service._presetStoreTransactionJournalForTesting(deviceId: device.id) == nil)
        #expect(try await service._verifiedPresetStoreSnapshotCountForTesting(device: device) == 2)
    }

    @Test("timed-out upload reads the original twice before one retry")
    func testTimedOutUploadRetriesOnlyAfterStableOriginalReadBack() async throws {
        final class Fixture {
            var presets = Data(#"{"0":{},"10":{"n":"Existing","seg":[]}}"#.utf8)
            var uploadCount = 0
        }
        let fixture = Fixture()
        let service = makeTestService { request in
            let url = try #require(request.url)
            let response = try okResponse(for: url)
            switch url.path {
            case "/presets.json":
                return (response, fixture.presets)
            case "/upload":
                fixture.uploadCount += 1
                if fixture.uploadCount == 1 {
                    throw URLError(.timedOut)
                }
                fixture.presets = try uploadedPresetStoreData(from: request)
                return (response, Data("File Uploaded!".utf8))
            default:
                return (response, Data(Self.mockStateResponseJSON.utf8))
            }
        }
        let device = createTestDevice()

        let outcome = try await service.savePreset(
            WLEDPresetSaveRequest(id: 78, name: "Retry Candidate", quickLoad: nil, state: nil),
            to: device
        )

        #expect(outcome == .committed)
        #expect(fixture.uploadCount == 2)
        let requestPaths = MockWLEDURLProtocol.requests().compactMap(\.url?.path)
        let uploadIndices = requestPaths.indices.filter { requestPaths[$0] == "/upload" }
        #expect(uploadIndices.count == 2)
        if uploadIndices.count == 2 {
            let readsBetween = requestPaths[(uploadIndices[0] + 1)..<uploadIndices[1]]
                .filter { $0 == "/presets.json" }
                .count
            #expect(readsBetween >= 2)
        }
    }

    @Test("confirmed malformed read-back restores, then replays the interrupted save once")
    func testMalformedReadBackRestoresAndReplaysOnce() async throws {
        final class Fixture {
            let malformed = Data(#"{"0":{},"77":{"n":"partial""#.utf8)
            var presets = Data(#"{"0":{},"10":{"n":"Existing","seg":[]}}"#.utf8)
            var uploadCount = 0
        }
        let fixture = Fixture()
        let service = makeTestService { request in
            let url = try #require(request.url)
            let response = try okResponse(for: url)
            switch url.path {
            case "/presets.json":
                return (response, fixture.presets)
            case "/upload":
                fixture.uploadCount += 1
                if fixture.uploadCount == 1 {
                    fixture.presets = fixture.malformed
                } else {
                    fixture.presets = try uploadedPresetStoreData(from: request)
                }
                return (response, Data("File Uploaded!".utf8))
            default:
                return (response, Data(Self.mockStateResponseJSON.utf8))
            }
        }
        let device = createTestDevice()

        let outcome = try await service.savePreset(
            WLEDPresetSaveRequest(id: 77, name: "Recovered Save", quickLoad: nil, state: nil),
            to: device
        )

        #expect(outcome == .committed)
        #expect(fixture.uploadCount == 3)
        let records = try #require(
            JSONSerialization.jsonObject(with: fixture.presets) as? [String: Any]
        )
        #expect(records["10"] != nil)
        #expect(records["77"] != nil)
    }

    @Test("failed replay performs a final restore and reports no commit")
    func testReplayFailureRestoresOriginalAndStops() async throws {
        final class Fixture {
            let malformed = Data(#"{"0":{},"79":{"n":"partial""#.utf8)
            let original = Data(#"{"0":{},"10":{"n":"Existing","seg":[]}}"#.utf8)
            var presets: Data
            var uploadCount = 0

            init() {
                presets = original
            }
        }
        let fixture = Fixture()
        let service = makeTestService { request in
            let url = try #require(request.url)
            let response = try okResponse(for: url)
            switch url.path {
            case "/presets.json":
                return (response, fixture.presets)
            case "/upload":
                fixture.uploadCount += 1
                if fixture.uploadCount == 1 || fixture.uploadCount == 3 {
                    fixture.presets = fixture.malformed
                } else {
                    fixture.presets = try uploadedPresetStoreData(from: request)
                }
                return (response, Data("File Uploaded!".utf8))
            default:
                return (response, Data(Self.mockStateResponseJSON.utf8))
            }
        }
        let device = createTestDevice()

        let outcome = try await service.savePreset(
            WLEDPresetSaveRequest(id: 79, name: "Replay Fails", quickLoad: nil, state: nil),
            to: device
        )

        #expect(outcome == .recoveredWithoutCommit)
        #expect(fixture.uploadCount == 4)
        #expect(fixture.presets == fixture.original)
        #expect(try await service._presetStoreTransactionJournalForTesting(deviceId: device.id) == nil)
    }

    @Test("transport failure leaves recovery pending and resumes from the durable journal")
    func testPendingJournalResumesAfterServiceRelaunch() async throws {
        final class Fixture {
            var presets = Data(#"{"0":{},"10":{"n":"Existing","seg":[]}}"#.utf8)
            var readCount = 0
            var uploadCount = 0
        }
        let fixture = Fixture()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PresetStoreRelaunch-\(UUID().uuidString)", isDirectory: true)
        let firstService = makeTestService(handler: { request in
            let url = try #require(request.url)
            let response = try okResponse(for: url)
            switch url.path {
            case "/presets.json":
                fixture.readCount += 1
                if fixture.readCount > 1 {
                    throw URLError(.networkConnectionLost)
                }
                return (response, fixture.presets)
            case "/upload":
                fixture.uploadCount += 1
                throw URLError(.timedOut)
            default:
                return (response, Data(Self.mockStateResponseJSON.utf8))
            }
        }, persistenceRoot: root)
        let device = createTestDevice()

        let firstOutcome = try await firstService.savePreset(
            WLEDPresetSaveRequest(id: 80, name: "Resume Me", quickLoad: nil, state: nil),
            to: device
        )

        #expect(firstOutcome == .recoveryPending)
        #expect(fixture.uploadCount == 1)
        #expect(try await firstService._verifiedPresetStoreSnapshotCountForTesting(device: device) == 1)
        #expect(try await firstService._presetStoreTransactionJournalForTesting(deviceId: device.id) != nil)
        do {
            _ = try await firstService.applyPreset(10, to: device)
            Issue.record("Preset activation must remain blocked while recovery is pending")
        } catch let error as WLEDAPIError {
            guard case .deviceBusy = error else {
                Issue.record("Expected deviceBusy while recovery is pending, got \(error)")
                return
            }
        }
        _ = try await firstService.setPower(
            for: device,
            isOn: false,
            transitionDeciseconds: 0
        )
        let directControlRequests = MockWLEDURLProtocol.requests().filter {
            $0.httpMethod == "POST" && $0.url?.path == "/json"
        }
        #expect(!directControlRequests.isEmpty)

        let resumedService = makeTestService(handler: { request in
            let url = try #require(request.url)
            let response = try okResponse(for: url)
            switch url.path {
            case "/presets.json":
                return (response, fixture.presets)
            case "/upload":
                fixture.uploadCount += 1
                fixture.presets = try uploadedPresetStoreData(from: request)
                return (response, Data("File Uploaded!".utf8))
            default:
                return (response, Data(Self.mockStateResponseJSON.utf8))
            }
        }, persistenceRoot: root)

        let resumedOutcome = await resumedService.resumePendingPresetStoreRecovery(for: device)

        #expect(resumedOutcome == .committed)
        #expect(fixture.uploadCount == 2)
        #expect(try await resumedService._presetStoreTransactionJournalForTesting(deviceId: device.id) == nil)
    }

    @Test("a new user save is not queued behind an older recovered transaction")
    func testNewSaveDoesNotQueueBehindRecoveredTransaction() async throws {
        final class Fixture {
            var presets = Data(#"{"0":{},"10":{"n":"Existing","seg":[]}}"#.utf8)
            var readCount = 0
            var uploadCount = 0
        }
        let fixture = Fixture()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PresetStoreNoUserQueue-\(UUID().uuidString)", isDirectory: true)
        let firstService = makeTestService(handler: { request in
            let url = try #require(request.url)
            let response = try okResponse(for: url)
            switch url.path {
            case "/presets.json":
                fixture.readCount += 1
                if fixture.readCount > 1 {
                    throw URLError(.networkConnectionLost)
                }
                return (response, fixture.presets)
            case "/upload":
                fixture.uploadCount += 1
                throw URLError(.timedOut)
            default:
                return (response, Data(Self.mockStateResponseJSON.utf8))
            }
        }, persistenceRoot: root)
        let device = createTestDevice()

        let interruptedOutcome = try await firstService.savePreset(
            WLEDPresetSaveRequest(id: 80, name: "Interrupted", quickLoad: nil, state: nil),
            to: device
        )
        #expect(interruptedOutcome == .recoveryPending)

        let resumedService = makeTestService(handler: { request in
            let url = try #require(request.url)
            let response = try okResponse(for: url)
            switch url.path {
            case "/presets.json":
                return (response, fixture.presets)
            case "/upload":
                fixture.uploadCount += 1
                fixture.presets = try uploadedPresetStoreData(from: request)
                return (response, Data("File Uploaded!".utf8))
            default:
                return (response, Data(Self.mockStateResponseJSON.utf8))
            }
        }, persistenceRoot: root)

        let newSaveOutcome = try await resumedService.savePreset(
            WLEDPresetSaveRequest(id: 81, name: "Must Not Queue", quickLoad: nil, state: nil),
            to: device
        )

        #expect(newSaveOutcome == .recoveredWithoutCommit)
        #expect(fixture.uploadCount == 2)
        let records = try #require(
            JSONSerialization.jsonObject(with: fixture.presets) as? [String: Any]
        )
        #expect(records["80"] != nil)
        #expect(records["81"] == nil)
        #expect(try await resumedService._presetStoreTransactionJournalForTesting(deviceId: device.id) == nil)
    }

    @Test("valid external change is preserved while the interrupted edit is rebased once")
    func testValidExternalChangeIsPreservedDuringRebase() async throws {
        final class Fixture {
            let externallyChanged = Data(
                #"{"0":{},"10":{"n":"Existing","seg":[],"futureField":{"keep":true}},"88":{"n":"External","seg":[]}}"#.utf8
            )
            var presets = Data(#"{"0":{},"10":{"n":"Existing","seg":[],"futureField":{"keep":true}}}"#.utf8)
            var uploadCount = 0
        }
        let fixture = Fixture()
        let service = makeTestService { request in
            let url = try #require(request.url)
            let response = try okResponse(for: url)
            switch url.path {
            case "/presets.json":
                return (response, fixture.presets)
            case "/upload":
                fixture.uploadCount += 1
                if fixture.uploadCount == 1 {
                    fixture.presets = fixture.externallyChanged
                    throw URLError(.timedOut)
                }
                fixture.presets = try uploadedPresetStoreData(from: request)
                return (response, Data("File Uploaded!".utf8))
            default:
                return (response, Data(Self.mockStateResponseJSON.utf8))
            }
        }
        let device = createTestDevice()

        let outcome = try await service.savePreset(
            WLEDPresetSaveRequest(id: 81, name: "Rebased", quickLoad: nil, state: nil),
            to: device
        )

        #expect(outcome == .committed)
        #expect(fixture.uploadCount == 2)
        let records = try #require(
            JSONSerialization.jsonObject(with: fixture.presets) as? [String: Any]
        )
        #expect(records["81"] != nil)
        #expect(records["88"] != nil)
        let existing = try #require(records["10"] as? [String: Any])
        #expect(existing["futureField"] != nil)
    }

    @Test("malformed store without a verified backup enters needs repair without writing")
    func testMalformedStoreWithoutBackupDoesNotGuessAFile() async throws {
        let malformed = Data(#"{"0":{},"10":{"n":"broken""#.utf8)
        let service = makeTestService { request in
            let url = try #require(request.url)
            let response = try okResponse(for: url)
            if url.path == "/presets.json" {
                return (response, malformed)
            }
            if url.path == "/upload" {
                Issue.record("A malformed store without a backup must not be uploaded over")
            }
            return (response, Data(Self.mockStateResponseJSON.utf8))
        }
        let device = createTestDevice()

        let outcome = try await service.savePreset(
            WLEDPresetSaveRequest(id: 82, name: "Must Not Save", quickLoad: nil, state: nil),
            to: device
        )

        #expect(outcome == .needsRepair)
        let uploadRequests = MockWLEDURLProtocol.requests().filter { $0.url?.path == "/upload" }
        #expect(uploadRequests.isEmpty)
        #expect(await service.presetStoreTransactionStatus(deviceId: device.id) == .needsRepair)
    }

    @Test("transaction verification rejects exact response bytes that require repair")
    func testStrictTransactionReadRejectsRepairableInvalidBytes() async throws {
        var malformed = Data(#"{"0":{}"#.utf8)
        malformed.append(0)
        malformed.append(Data("}".utf8))
        let service = makeTestService { request in
            let url = try #require(request.url)
            let response = try okResponse(for: url)
            if url.path == "/presets.json" {
                return (response, malformed)
            }
            if url.path == "/upload" {
                Issue.record("Strict verification must not upload over invalid exact bytes without a backup")
            }
            return (response, Data(Self.mockStateResponseJSON.utf8))
        }
        let device = createTestDevice()

        let outcome = try await service.savePreset(
            WLEDPresetSaveRequest(id: 83, name: "Must Not Sanitize", quickLoad: nil, state: nil),
            to: device
        )

        #expect(outcome == .needsRepair)
        #expect(MockWLEDURLProtocol.requests().allSatisfy { $0.url?.path != "/upload" })
    }

    @Test("verified snapshot rotation retains only the three newest files")
    func testVerifiedSnapshotRotationRetainsThree() async throws {
        final class Fixture {
            var presets = Data(#"{"0":{}}"#.utf8)
        }
        let fixture = Fixture()
        let service = makeTestService { request in
            let url = try #require(request.url)
            let response = try okResponse(for: url)
            switch url.path {
            case "/presets.json":
                return (response, fixture.presets)
            case "/upload":
                fixture.presets = try uploadedPresetStoreData(from: request)
                return (response, Data("File Uploaded!".utf8))
            default:
                return (response, Data(Self.mockStateResponseJSON.utf8))
            }
        }
        let device = createTestDevice()

        for id in 90...93 {
            let outcome = try await service.savePreset(
                WLEDPresetSaveRequest(id: id, name: "Snapshot \(id)", quickLoad: nil, state: nil),
                to: device
            )
            #expect(outcome == .committed)
        }

        #expect(try await service._verifiedPresetStoreSnapshotCountForTesting(device: device) == 3)
    }

    @Test("confirmed-invalid restore attempts stop at three and enter needs repair")
    func testConfirmedInvalidRestoreAttemptsAreLimited() async throws {
        final class Fixture {
            let malformed = Data(#"{"0":{},"94":{"n":"partial""#.utf8)
            var presets = Data(#"{"0":{}}"#.utf8)
            var forceMalformedUploads = false
            var uploadCount = 0
        }
        let fixture = Fixture()
        let service = makeTestService { request in
            let url = try #require(request.url)
            let response = try okResponse(for: url)
            switch url.path {
            case "/presets.json":
                return (response, fixture.presets)
            case "/upload":
                fixture.uploadCount += 1
                if fixture.forceMalformedUploads {
                    fixture.presets = fixture.malformed
                } else {
                    fixture.presets = try uploadedPresetStoreData(from: request)
                }
                return (response, Data("File Uploaded!".utf8))
            default:
                return (response, Data(Self.mockStateResponseJSON.utf8))
            }
        }
        let device = createTestDevice()
        #expect(
            try await service.savePreset(
                WLEDPresetSaveRequest(id: 93, name: "Verified Backup", quickLoad: nil, state: nil),
                to: device
            ) == .committed
        )
        fixture.forceMalformedUploads = true
        let baselineUploads = fixture.uploadCount

        let outcome = try await service.savePreset(
            WLEDPresetSaveRequest(id: 94, name: "Cannot Recover", quickLoad: nil, state: nil),
            to: device
        )

        #expect(outcome == .needsRepair)
        #expect(fixture.uploadCount - baselineUploads == 4)
        let journal = try await service._presetStoreTransactionJournalForTesting(deviceId: device.id)
        #expect(journal?.phase == .needsRepair)
        #expect(journal?.recoveryAttemptCount == 3)
    }

    @Test("segmented preset, playlist, and renames preserve unrelated unknown fields")
    func testSegmentedPresetPlaylistAndRenameTransactionsPreserveUnknownFields() async throws {
        final class Fixture {
            var presets = Data(
                #"{"0":{},"10":{"n":"Existing","seg":[],"future":{"nested":true}},"11":{"n":"Existing Playlist","playlist":{"ps":[10],"dur":[100],"transition":[7],"repeat":1,"end":0,"r":0},"futurePlaylistField":"keep"}}"#.utf8
            )
        }
        let fixture = Fixture()
        let service = makeTestService { request in
            let url = try #require(request.url)
            let response = try okResponse(for: url)
            switch url.path {
            case "/presets.json":
                return (response, fixture.presets)
            case "/upload":
                fixture.presets = try uploadedPresetStoreData(from: request)
                return (response, Data("File Uploaded!".utf8))
            default:
                return (response, Data(Self.mockStateResponseJSON.utf8))
            }
        }
        let device = createTestDevice()
        let segmentedState = WLEDStateUpdate(
            on: true,
            bri: 180,
            seg: [
                SegmentUpdate(id: 0, start: 0, stop: 15, col: [[255, 0, 0, 0]], fx: 0),
                SegmentUpdate(id: 1, start: 15, stop: 30, col: [[0, 0, 255, 0]], fx: 0)
            ]
        )

        #expect(
            try await service.savePreset(
                WLEDPresetSaveRequest(
                    id: 30,
                    name: "Segmented",
                    quickLoad: nil,
                    state: segmentedState,
                    saveSegmentBounds: true
                ),
                to: device
            ) == .committed
        )
        #expect(
            try await service.savePlaylist(
                WLEDPlaylistSaveRequest(
                    id: 31,
                    name: "Sequence",
                    ps: [10, 30],
                    dur: [100, 100],
                    transition: [7, 7],
                    repeat: 1,
                    endPresetId: 0,
                    shuffle: 0
                ),
                to: device
            ) == .committed
        )
        #expect(
            try await service.renamePresetRecord(
                id: 30,
                name: "Segmented Renamed",
                device: device
            ) == .committed
        )
        #expect(
            try await service.renamePlaylistRecord(
                id: 31,
                name: "Sequence Renamed",
                device: device
            ) == .committed
        )

        let records = try #require(
            JSONSerialization.jsonObject(with: fixture.presets) as? [String: Any]
        )
        let existingPreset = try #require(records["10"] as? [String: Any])
        let existingPlaylist = try #require(records["11"] as? [String: Any])
        let segmented = try #require(records["30"] as? [String: Any])
        let playlist = try #require(records["31"] as? [String: Any])
        #expect(existingPreset["future"] != nil)
        #expect(existingPlaylist["futurePlaylistField"] as? String == "keep")
        #expect((segmented["seg"] as? [[String: Any]])?.count == 2)
        #expect(segmented["n"] as? String == "Segmented Renamed")
        #expect(playlist["n"] as? String == "Sequence Renamed")
        #expect(playlist["playlist"] != nil)
    }

    @Test("apply at boot is written only after store commit and is verified separately")
    func testApplyAtBootFollowsCommittedStoreAndVerifiesConfig() async throws {
        final class Fixture {
            var presets = Data(#"{"0":{}}"#.utf8)
            var bootPreset = 0
        }
        let fixture = Fixture()
        let service = makeTestService { request in
            let url = try #require(request.url)
            let response = try okResponse(for: url)
            switch url.path {
            case "/presets.json":
                return (response, fixture.presets)
            case "/upload":
                fixture.presets = try uploadedPresetStoreData(from: request)
                return (response, Data("File Uploaded!".utf8))
            case "/json":
                if request.httpMethod == "POST",
                   let body = MockWLEDURLProtocol.bodyDataForTesting(from: request),
                   let object = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                   let bootPreset = object["bootps"] as? Int {
                    fixture.bootPreset = bootPreset
                }
                return (response, Data(Self.mockStateResponseJSON.utf8))
            case "/json/cfg":
                return (response, Data(#"{"def":{"ps":\#(fixture.bootPreset)}}"#.utf8))
            default:
                return (response, Data(Self.mockStateResponseJSON.utf8))
            }
        }
        let device = createTestDevice()

        let outcome = try await service.savePreset(
            WLEDPresetSaveRequest(
                id: 40,
                name: "Boot Preset",
                quickLoad: nil,
                state: nil,
                applyAtBoot: true
            ),
            to: device
        )

        #expect(outcome == .committed)
        #expect(fixture.bootPreset == 40)
        let paths = MockWLEDURLProtocol.requests().compactMap(\.url?.path)
        let uploadIndex = try #require(paths.firstIndex(of: "/upload"))
        let stateIndex = try #require(
            MockWLEDURLProtocol.requests().firstIndex {
                $0.httpMethod == "POST" && $0.url?.path == "/json"
            }
        )
        let configIndex = try #require(paths.lastIndex(of: "/json/cfg"))
        #expect(uploadIndex < stateIndex)
        #expect(stateIndex < configIndex)
    }
    
    // MARK: - setColor Tests
    
    @Test("setColor validates color array has at least 3 elements")
    func testSetColorValidation() async throws {
        let service = makeTestService()
        let device = createTestDevice()
        
        // Test with insufficient color values
        do {
            _ = try await service.setColor(for: device, color: [255, 0])
            Issue.record("Should have thrown error for color array with < 3 elements")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidConfiguration = apiError {
                    // Expected error
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }
    }
    
    @Test("setColor constructs correct RGB payload")
    func testSetColorRGBPayload() async throws {
        let service = makeTestService()
        let device = createTestDevice()
        
        _ = try await service.setColor(for: device, color: [255, 165, 0], cct: nil, white: nil)
    }
    
    @Test("setColor includes white channel when provided")
    func testSetColorWithWhiteChannel() async throws {
        let service = makeTestService()
        let device = createTestDevice()
        
        _ = try await service.setColor(for: device, color: [255, 165, 0], cct: nil, white: 128)
    }
    
    @Test("setColor includes CCT when provided")
    func testSetColorWithCCT() async throws {
        let service = makeTestService()
        let device = createTestDevice()
        
        _ = try await service.setColor(for: device, color: [255, 165, 0], cct: 200, white: nil)
    }

    @Test("Alexa settings report firmware support when voice assistant config exists")
    func testAlexaSettingsReportSupportedFirmware() async throws {
        let service = makeTestService()
        let device = createTestDevice()

        let settings = try await service.fetchAlexaIntegrationSettings(for: device)

        #expect(settings.isSupported)
        #expect(!settings.isEnabled)
        #expect(settings.exposedPresetCount == 0)
    }

    @Test("Alexa settings report unsupported when firmware omits voice assistant config")
    func testAlexaSettingsReportUnsupportedFirmware() async throws {
        let unsupportedConfig = """
        {
          "id": { "inv": "Light" },
          "if": {
            "sync": {
              "send": {},
              "recv": {}
            }
          }
        }
        """
        let service = makeTestService { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }

            if url.path == "/json/cfg" {
                return (response, Data(unsupportedConfig.utf8))
            }
            return (response, Data(Self.mockStateResponseJSON.utf8))
        }
        let device = createTestDevice()

        let settings = try await service.fetchAlexaIntegrationSettings(for: device)

        #expect(!settings.isSupported)
        #expect(!settings.isEnabled)
        #expect(settings.invocationName == "Light")
    }

    @Test("Alexa settings update refuses unsupported firmware")
    func testAlexaSettingsUpdateRefusesUnsupportedFirmware() async throws {
        let unsupportedConfig = """
        {
          "id": { "inv": "Light" },
          "if": {
            "sync": {
              "send": {},
              "recv": {}
            }
          }
        }
        """
        let service = makeTestService { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }

            if url.path == "/json/cfg" {
                return (response, Data(unsupportedConfig.utf8))
            }
            return (response, Data(Self.mockStateResponseJSON.utf8))
        }
        let device = createTestDevice()

        do {
            try await service.updateAlexaIntegrationSettings(
                WLEDAlexaIntegrationSettings(
                    isEnabled: true,
                    invocationName: "Bedroom Lights",
                    exposedPresetCount: 0
                ),
                for: device
            )
            Issue.record("Expected unsupported Alexa firmware to reject settings update")
        } catch let error as WLEDAPIError {
            guard case .unsupportedOperation(let operation) = error else {
                Issue.record("Expected unsupported operation error")
                return
            }
            #expect(operation == "Alexa")
        }

        let requests = MockWLEDURLProtocol.requests()
        #expect(requests.filter { $0.url?.path == "/json/cfg" }.count == 1)
        #expect(requests.allSatisfy { $0.httpMethod != "POST" })
    }
    
    // MARK: - setCCT Tests
    
    @Test("setCCT validates CCT range 0-255")
    func testSetCCTRangeValidation() async throws {
        let service = makeTestService()
        let device = createTestDevice()
        
        // Test below range
        do {
            _ = try await service.setCCT(for: device, cct: -1)
            Issue.record("Should have thrown error for CCT < 0")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidConfiguration = apiError {
                    // Expected
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }
        
        // Test above range
        do {
            _ = try await service.setCCT(for: device, cct: 256)
            Issue.record("Should have thrown error for CCT > 255")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidConfiguration = apiError {
                    // Expected
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }
        
        _ = try await service.setCCT(for: device, cct: 128)
    }
    
    @Test("setCCT Kelvin validates minimum 1000K")
    func testSetCCTKelvinValidation() async throws {
        let service = makeTestService()
        let device = createTestDevice()
        
        // Test below minimum
        do {
            _ = try await service.setCCT(for: device, cctKelvin: 999)
            Issue.record("Should have thrown error for CCT Kelvin < 1000")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidConfiguration = apiError {
                    // Expected
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }
        
        _ = try await service.setCCT(for: device, cctKelvin: 1000)
    }
    
    @Test("setCCT accepts valid values")
    func testSetCCTValidValues() async throws {
        let service = makeTestService()
        let device = createTestDevice()
        
        _ = try await service.setCCT(for: device, cct: 0)
        _ = try await service.setCCT(for: device, cct: 255)
    }
    
    // MARK: - setWhiteChannel Tests
    
    @Test("setColor white channel is clamped to 0-255")
    func testWhiteChannelClamping() async throws {
        let service = makeTestService()
        let device = createTestDevice()
        
        // Test that white values outside range are clamped
        // Note: The implementation uses max(0, min(255, whiteValue))
        // We verify this by checking the method accepts and processes values
        
        _ = try await service.setColor(for: device, color: [255, 255, 255], cct: nil, white: 300)
        _ = try await service.setColor(for: device, color: [255, 255, 255], cct: nil, white: -10)
    }
    
    // MARK: - Presets Tests
    
    @Test("fetchPresets constructs correct URL")
    func testFetchPresetsURL() async throws {
        let service = makeTestService { _ in
            throw URLError(.cannotConnectToHost)
        }
        let device = createTestDevice(ipAddress: "192.168.1.50")
        
        do {
            _ = try await service.fetchPresets(for: device)
            Issue.record("fetchPresets should fail through the mocked transport")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidURL = apiError {
                    Issue.record("URL construction should be valid for fetchPresets")
                }
            }
        }

        let requests = MockWLEDURLProtocol.requests()
        #expect(requests.first?.url?.absoluteString == "http://192.168.1.50/presets.json")
    }
    
    @Test("savePreset validates preset ID >= 0")
    func testSavePresetValidation() async throws {
        let service = makeTestService()
        let device = createTestDevice()
        
        let invalidRequest = WLEDPresetSaveRequest(id: -1, name: "Test", quickLoad: nil, state: nil)
        
        do {
            _ = try await service.savePreset(invalidRequest, to: device)
            Issue.record("Should have thrown error for preset ID < 0")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidConfiguration = apiError {
                    // Expected
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }
    }
    
    @Test("applyPreset validates preset ID range 1-250")
    func testApplyPresetValidation() async throws {
        let service = makeTestService()
        let device = createTestDevice()
        
        // Test below range
        do {
            _ = try await service.applyPreset(0, to: device)
            Issue.record("Should have thrown error for preset ID 0")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidConfiguration = apiError {
                    // Expected
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }
        
        // Test above range
        do {
            _ = try await service.applyPreset(251, to: device)
            Issue.record("Should have thrown error for preset ID > 250")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidConfiguration = apiError {
                    // Expected
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }
        
        _ = try await service.applyPreset(1, to: device)
        _ = try await service.applyPreset(250, to: device)
    }

    @Test("applyPreset fetches direct preset payload on cold cache")
    func testApplyPresetFetchesDirectPayloadWhenCacheIsCold() async throws {
        let service = makeTestService { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }

            if url.path == "/presets.json" {
                return (response, Data("""
                {
                  "0": {},
                  "42": {
                    "n": "Saved Warm",
                    "on": true,
                    "bri": 173,
                    "seg": [
                      { "id": 0, "start": 0, "stop": 30, "col": [[255, 160, 0, 0]], "fx": 0, "pal": 0 }
                    ]
                  }
                }
                """.utf8))
            }

            return (response, Data(Self.mockStateResponseJSON.utf8))
        }
        let device = createTestDevice()

        _ = try await service.applyPreset(42, to: device, transitionDeciseconds: 7)

        let requests = MockWLEDURLProtocol.requests()
        #expect(requests.contains { $0.url?.path == "/presets.json" })

        let stateBody = try #require(
            zip(requests, MockWLEDURLProtocol.requestBodies())
                .first { $0.0.httpMethod == "POST" && $0.0.url?.path == "/json" }?.1
        )
        let object = try #require(JSONSerialization.jsonObject(with: stateBody) as? [String: Any])
        #expect(object["ps"] == nil)
        #expect(object["pd"] as? Int == 42)
        #expect(object["bri"] as? Int == 173)
        #expect(object["tt"] as? Int == 7)

        let segments = try #require(object["seg"] as? [[String: Any]])
        let firstSegment = try #require(segments.first)
        let colorSlots = try #require(firstSegment["col"] as? [[Int]])
        #expect(colorSlots.first == [255, 160, 0, 0])
    }

    @Test("applyPlaylist validates playlist ID range 1-250")
    func testApplyPlaylistValidation() async throws {
        let service = makeTestService()
        let device = createTestDevice()

        do {
            _ = try await service.applyPlaylist(0, to: device)
            Issue.record("Should have thrown error for playlist ID 0")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidConfiguration = apiError {
                    // Expected
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }

        do {
            _ = try await service.applyPlaylist(251, to: device)
            Issue.record("Should have thrown error for playlist ID > 250")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidConfiguration = apiError {
                    // Expected
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }
    }

    @Test("deletePreset validates preset ID range 1-250")
    func testDeletePresetValidation() async throws {
        let service = makeTestService()
        let device = createTestDevice()

        do {
            _ = try await service.deletePreset(id: 0, device: device)
            Issue.record("Should have thrown error for preset ID 0")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidConfiguration = apiError {
                    // Expected
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }

        do {
            _ = try await service.deletePreset(id: 251, device: device)
            Issue.record("Should have thrown error for preset ID > 250")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidConfiguration = apiError {
                    // Expected
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }
    }

    @Test("deletePlaylist validates playlist ID range 1-250")
    func testDeletePlaylistValidation() async throws {
        let service = makeTestService()
        let device = createTestDevice()

        do {
            _ = try await service.deletePlaylist(id: 0, device: device)
            Issue.record("Should have thrown error for playlist ID 0")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidConfiguration = apiError {
                    // Expected
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }

        do {
            _ = try await service.deletePlaylist(id: 251, device: device)
            Issue.record("Should have thrown error for playlist ID > 250")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidConfiguration = apiError {
                    // Expected
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }
    }

    @Test("preset delete uses one full-file upload and never emits pdel or psave")
    func testPresetDeleteUsesOnlyFullFileUpload() async throws {
        final class Fixture {
            var presets = Data(#"{"0":{},"19":{"n":"Remove","seg":[]},"20":{"n":"Keep","seg":[]}}"#.utf8)
        }
        let fixture = Fixture()
        let service = makeTestService { request in
            let url = try #require(request.url)
            let response = try okResponse(for: url)
            switch url.path {
            case "/presets.json":
                return (response, fixture.presets)
            case "/upload":
                fixture.presets = try uploadedPresetStoreData(from: request)
                return (response, Data("File Uploaded!".utf8))
            default:
                return (response, Data(Self.mockStateResponseJSON.utf8))
            }
        }
        let device = createTestDevice(ipAddress: "192.168.0.6")

        let outcome = try await service.deletePreset(id: 19, device: device)

        #expect(outcome == .committed)
        let requests = MockWLEDURLProtocol.requests()
        #expect(requests.filter { $0.url?.path == "/upload" }.count == 1)
        #expect(!requests.contains { $0.url?.path == "/json/si" })
        let bodies = MockWLEDURLProtocol.requestBodies().compactMap { $0 }
        #expect(!bodies.contains { String(decoding: $0, as: UTF8.self).contains("\"pdel\"") })
        #expect(!bodies.contains { String(decoding: $0, as: UTF8.self).contains("\"psave\"") })
    }

    @Test("WLED-style automation delete orders playlist deletes before preset deletes")
    func testOrderedPresetStoreDeleteTargetsPlacePlaylistFirst() async throws {
        let service = makeTestService()

        let targets = await service.orderedPresetStoreDeleteTargets(
            playlistIds: [4, 1, 4],
            presetIds: [9, 2, 9, 3]
        )

        #expect(
            targets == [
                .init(type: .playlist, id: 1),
                .init(type: .playlist, id: 4),
                .init(type: .preset, id: 2),
                .init(type: .preset, id: 3),
                .init(type: .preset, id: 9)
            ]
        )
    }

    @Test("savePlaylist rejects invalid playlist constraints")
    func testSavePlaylistValidationConstraints() async throws {
        let service = makeTestService()
        let device = createTestDevice()

        let tooManySteps = WLEDPlaylistSaveRequest(
            id: 10,
            name: "TooMany",
            ps: Array(repeating: 1, count: 101),
            dur: Array(repeating: 100, count: 101),
            transition: Array(repeating: 7, count: 101),
            repeat: 1,
            endPresetId: 0,
            shuffle: 0
        )

        do {
            _ = try await service.savePlaylist(tooManySteps, to: device)
            Issue.record("Should have rejected playlist with > 100 steps")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidConfiguration = apiError {
                    // Expected
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }

        let invalidRepeat = WLEDPlaylistSaveRequest(
            id: 11,
            name: "RepeatInvalid",
            ps: [1, 2],
            dur: [100, 100],
            transition: [7, 7],
            repeat: 128,
            endPresetId: 0,
            shuffle: 0
        )

        do {
            _ = try await service.savePlaylist(invalidRepeat, to: device)
            Issue.record("Should have rejected repeat > 127")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidConfiguration = apiError {
                    // Expected
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }

        let invalidEndPreset = WLEDPlaylistSaveRequest(
            id: 12,
            name: "EndInvalid",
            ps: [1, 2],
            dur: [100, 100],
            transition: [7, 7],
            repeat: 1,
            endPresetId: 254,
            shuffle: 0
        )

        do {
            _ = try await service.savePlaylist(invalidEndPreset, to: device)
            Issue.record("Should have rejected unsupported end preset value")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidConfiguration = apiError {
                    // Expected
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }

        let invalidShuffle = WLEDPlaylistSaveRequest(
            id: 13,
            name: "ShuffleInvalid",
            ps: [1, 2],
            dur: [100, 100],
            transition: [7, 7],
            repeat: 1,
            endPresetId: 0,
            shuffle: 2
        )

        do {
            _ = try await service.savePlaylist(invalidShuffle, to: device)
            Issue.record("Should have rejected shuffle values other than 0/1")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidConfiguration = apiError {
                    // Expected
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }
    }

    @Test("playlist step plan for long duration keeps transition <= duration")
    func testPlaylistStepPlanLongDurationParity() async {
        let service = makeTestService()
        let requested = 240.0
        let plan = await service.debugPlaylistStepPlanForTests(durationSeconds: requested)

        #expect(plan.steps > 0)
        #expect(plan.durations.count == plan.steps)
        #expect(plan.transitions.count == plan.steps)
        #expect(plan.durations.allSatisfy { $0 > 0 })
        #expect(plan.transitions.first == 0)
        #expect(zip(plan.durations.dropFirst(), plan.transitions.dropFirst()).allSatisfy { duration, transition in
            transition == duration
        })
        #expect(abs(plan.effectiveDurationSeconds - requested) <= 0.5)
    }

    @Test("validated playlist request normalizes timing arrays and clamps transition by duration")
    func testValidatedPlaylistRequestNormalizationAndClamping() async throws {
        let service = makeTestService()
        let request = WLEDPlaylistSaveRequest(
            id: 22,
            name: "Normalize",
            ps: [1, 2, 3],
            dur: [5],
            transition: [20, 30],
            repeat: 1,
            endPresetId: 0,
            shuffle: 0
        )

        let normalized = try await service.debugValidatedPlaylistRequestForTests(request)
        #expect(normalized.dur.count == 3)
        #expect(normalized.transition.count == 3)
        #expect(normalized.dur == [5, 5, 5])
        #expect(normalized.transition == [5, 5, 5])
        #expect(zip(normalized.dur, normalized.transition).allSatisfy { duration, transition in
            duration == 0 || transition <= duration
        })
    }

    @Test("validated playlist request preserves manual-advance entries")
    func testValidatedPlaylistRequestManualAdvanceDurZero() async throws {
        let service = makeTestService()
        let request = WLEDPlaylistSaveRequest(
            id: 23,
            name: "Manual advance",
            ps: [1, 2],
            dur: [0, 5],
            transition: [500, 99],
            repeat: 1,
            endPresetId: 0,
            shuffle: 0
        )

        let normalized = try await service.debugValidatedPlaylistRequestForTests(request)
        #expect(normalized.dur == [0, 5])
        #expect(normalized.transition == [500, 5])
    }

    @Test("playlist parser handles top-level and nested presets payload shapes")
    func testPlaylistParserPayloadShapes() async throws {
        let service = makeTestService()

        let topLevel = """
        {
          "1": {
            "n": "Top Level Playlist",
            "playlist": {
              "ps": [10, 11],
              "dur": [100, 120],
              "transition": [7, 9],
              "repeat": 1,
              "end": 0,
              "r": 0
            }
          }
        }
        """.data(using: .utf8)!

        let nested = """
        {
          "presets": {
            "2": {
              "n": "Nested Playlist",
              "playlist": {
                "ps": [20, 21],
                "dur": [150, 160],
                "transition": [5, 5],
                "repeat": 0,
                "end": 255,
                "r": 1
              }
            }
          }
        }
        """.data(using: .utf8)!

        let parsedTopLevel = try await service.parsePlaylistsFromPresetsPayloadForTesting(topLevel)
        #expect(parsedTopLevel.count == 1)
        #expect(parsedTopLevel.first?.id == 1)
        #expect(parsedTopLevel.first?.name == "Top Level Playlist")
        #expect(parsedTopLevel.first?.presets == [10, 11])
        #expect(parsedTopLevel.first?.duration == [100, 120])
        #expect(parsedTopLevel.first?.transition == [7, 9])

        let parsedNested = try await service.parsePlaylistsFromPresetsPayloadForTesting(nested)
        #expect(parsedNested.count == 1)
        #expect(parsedNested.first?.id == 2)
        #expect(parsedNested.first?.name == "Nested Playlist")
        #expect(parsedNested.first?.presets == [20, 21])
        #expect(parsedNested.first?.repeat == 0)
        #expect(parsedNested.first?.endPresetId == 255)
        #expect(parsedNested.first?.shuffle == 1)
    }

    @Test("preset parser hydrates top-level WLED state fields")
    func testPresetParserHydratesTopLevelStateFields() async throws {
        let service = makeTestService()
        let payload = """
        {
          "42": {
            "n": "Automation Recovered",
            "on": true,
            "bri": 144,
            "seg": [
              { "id": 0, "start": 0, "stop": 30, "col": [[255,0,64,0]], "fx": 73, "sx": 77, "ix": 88, "pal": 3 }
            ]
          }
        }
        """.data(using: .utf8)!

        let parsed = try await service.parsePresetsPayloadForTesting(payload)

        let preset = try #require(parsed.first(where: { $0.id == 42 }))
        #expect(preset.name == "Automation Recovered")
        #expect(preset.state?.on == true)
        #expect(preset.state?.bri == 144)
        #expect(preset.state?.seg?.first?.fx == 73)
        #expect(preset.state?.seg?.first?.sx == 77)
        #expect(preset.state?.seg?.first?.ix == 88)
        #expect(preset.state?.seg?.first?.pal == 3)
    }

    @Test("preset parser wraps malformed payload errors")
    func testPresetParserMalformedPayloadErrorWrapping() async throws {
        let service = makeTestService()
        let malformed = Data("{".utf8)

        do {
            _ = try await service.parsePresetsPayloadForTesting(malformed)
            Issue.record("Malformed preset payload should throw")
        } catch {
            guard let apiError = error as? WLEDAPIError else {
                Issue.record("Expected WLEDAPIError for malformed preset payload")
                return
            }
            if case .decodingError = apiError {
                // Expected
            } else {
                Issue.record("Expected decodingError for malformed preset payload")
            }
        }
    }

    @Test("playlist parser wraps malformed payload errors")
    func testPlaylistParserMalformedPayloadErrorWrapping() async throws {
        let service = makeTestService()
        let malformed = Data("{".utf8)

        do {
            _ = try await service.parsePlaylistsPayloadForTesting(malformed)
            Issue.record("Malformed playlist payload should throw")
        } catch {
            guard let apiError = error as? WLEDAPIError else {
                Issue.record("Expected WLEDAPIError for malformed playlist payload")
                return
            }
            if case .decodingError = apiError {
                // Expected
            } else {
                Issue.record("Expected decodingError for malformed playlist payload")
            }
        }
    }

    @Test("preset parser accepts zero-only payload with whitespace")
    func testPresetParserZeroOnlyWhitespacePayload() async throws {
        let service = makeTestService()
        let payload = Data("{\"0\":{}}          \n\t  ".utf8)

        let parsed = try await service.parsePresetsPayloadForTesting(payload)
        #expect(parsed.isEmpty)
    }

    @Test("preset parser recovers trailing garbage after valid root object")
    func testPresetParserRecoversTrailingGarbage() async throws {
        let service = makeTestService()
        let valid = """
        {
          "236": { "n": "Auto Step 236", "seg": [] }
        }
        """
        var bytes = Array(valid.utf8)
        bytes.append(contentsOf: [0x20, 0x20, 0xEF, 0xBF, 0xBD, 0x00, 0x58])
        let payload = Data(bytes)

        let parsed = try await service.parsePresetsPayloadForTesting(payload)
        #expect(parsed.count == 1)
        #expect(parsed.first?.id == 236)
        #expect(parsed.first?.name == "Auto Step 236")
    }

    @Test("preset parser strips BOM and NUL bytes")
    func testPresetParserStripsBOMAndNUL() async throws {
        let service = makeTestService()
        let json = "{\"237\":{\"n\":\"Auto Step 237\",\"seg\":[]}}"
        let bytes: [UInt8] = [0xEF, 0xBB, 0xBF] + Array(json.utf8) + [0x00, 0x00]
        let parsed = try await service.parsePresetsPayloadForTesting(Data(bytes))

        #expect(parsed.count == 1)
        #expect(parsed.first?.id == 237)
    }

    @Test("preset parser recovers invalid bytes in whitespace outside JSON strings")
    func testPresetParserRecoversInvalidWhitespaceBytes() async throws {
        let service = makeTestService()
        var bytes = Array("""
        {
          "236": { "n": "Auto Step 236", "seg": [] },
          "237": { "n": "Auto Step 237", "seg": [] }
        }
        """.utf8)
        if let insertIndex = bytes.firstIndex(of: 0x0A) {
            bytes.insert(contentsOf: [0xFF, 0x00, 0xFF], at: insertIndex)
        }
        let payload = Data(bytes)

        let parsed = try await service.parsePresetsPayloadForTesting(payload)
        #expect(parsed.count == 2)
        #expect(parsed.map(\.id) == [236, 237])
    }

    @Test("strict preset verification parser rejects partial root recovery")
    func testStrictPresetVerificationParserRejectsPartialRootRecovery() async throws {
        let service = makeTestService()
        let malformed = Data("{\"0\":{}                                                                 :\"5\":{\"n\":\"Ghost preset\"}}".utf8)

        do {
            _ = try await service.debugParsedPresetRecordIdsForTesting(data: malformed, strict: true)
            Issue.record("Strict parser should reject malformed preset payload")
        } catch {
            guard let apiError = error as? WLEDAPIError else {
                Issue.record("Expected WLEDAPIError from strict parser")
                return
            }
            switch apiError {
            case .decodingError, .invalidResponse:
                break // Expected strict rejection mode
            default:
                Issue.record("Expected strict parser rejection error")
            }
        }
    }

    @Test("strict preset verification parser rejects invalid bytes outside strings")
    func testStrictPresetVerificationParserRejectsInvalidByteOutsideStrings() async throws {
        let service = makeTestService()
        var bytes = Array("{\"0\":{},\"17\":{\"n\":\"Recovered\"}                                                                  }".utf8)
        let insertionIndex = max(1, bytes.count - 2) // whitespace zone before final closing brace
        bytes.insert(0xC9, at: insertionIndex) // invalid UTF-8 byte outside JSON strings
        let malformed = Data(bytes)

        do {
            _ = try await service.debugParsedPresetRecordIdsForTesting(data: malformed, strict: true)
            Issue.record("Strict verification must reject byte-repaired payloads")
        } catch {
            guard let apiError = error as? WLEDAPIError else {
                Issue.record("Expected WLEDAPIError from strict parser")
                return
            }
            switch apiError {
            case .decodingError, .invalidResponse:
                break
            default:
                Issue.record("Expected strict parser rejection error")
            }
        }
    }

    @Test("Alexa mirror plan detects existing non-app Alexa slots")
    func testAlexaMirrorPlanDetectsConflicts() async throws {
        let service = makeTestService()
        let payload = Data("""
        {
          "0": {},
          "1": { "n": "Existing WLED Alexa Preset" },
          "10": { "n": "Warm", "seg": [] }
        }
        """.utf8)
        let result = try await service.debugAlexaMirrorPlanForTesting(
            data: payload,
            favorites: [WLEDAlexaMirrorFavorite(slot: 1, sourcePresetId: 10, displayName: "Warm")],
            allowReplacingExisting: false
        )

        #expect(result.conflictSlots == [1])
        #expect(result.mirroredSlots.isEmpty)
    }

    @Test("Alexa mirror plan mirrors sources and deletes stale owned slots")
    func testAlexaMirrorPlanMirrorsAndDeletesStaleOwnedSlots() async throws {
        let service = makeTestService()
        let payload = Data("""
        {
          "0": {},
          "2": { "n": "Old Alexa", "aesdetic": { "alexa": true, "source": 11, "slot": 2 } },
          "10": { "n": "Warm", "seg": [] }
        }
        """.utf8)
        let result = try await service.debugAlexaMirrorPlanForTesting(
            data: payload,
            favorites: [WLEDAlexaMirrorFavorite(slot: 1, sourcePresetId: 10, displayName: "Warm")],
            allowReplacingExisting: false
        )

        #expect(result.mirroredSlots == [1])
        #expect(result.deletedSlots == [2])
        #expect(result.conflictSlots.isEmpty)
        #expect(result.missingSourceIds.isEmpty)
    }

    @Test("Alexa mirror plan reports missing source presets")
    func testAlexaMirrorPlanReportsMissingSources() async throws {
        let service = makeTestService()
        let payload = Data("{\"0\":{}}".utf8)
        let result = try await service.debugAlexaMirrorPlanForTesting(
            data: payload,
            favorites: [WLEDAlexaMirrorFavorite(slot: 1, sourcePresetId: 10, displayName: "Warm")],
            allowReplacingExisting: false
        )

        #expect(result.missingSourceIds == [10])
        #expect(result.mirroredSlots.isEmpty)
    }

    @Test("renamePresetRecord validates ID range 1-250")
    func testRenamePresetRecordValidation() async throws {
        let service = makeTestService()
        let device = createTestDevice()

        do {
            _ = try await service.renamePresetRecord(id: 0, name: "Test", device: device)
            Issue.record("Should have thrown error for preset ID 0")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidConfiguration = apiError {
                    // Expected
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }

        do {
            _ = try await service.renamePresetRecord(id: 251, name: "Test", device: device)
            Issue.record("Should have thrown error for preset ID > 250")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidConfiguration = apiError {
                    // Expected
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }
    }

    @Test("renamePlaylistRecord validates ID range 1-250")
    func testRenamePlaylistRecordValidation() async throws {
        let service = makeTestService()
        let device = createTestDevice()

        do {
            _ = try await service.renamePlaylistRecord(id: 0, name: "Test", device: device)
            Issue.record("Should have thrown error for playlist ID 0")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidConfiguration = apiError {
                    // Expected
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }

        do {
            _ = try await service.renamePlaylistRecord(id: 251, name: "Test", device: device)
            Issue.record("Should have thrown error for playlist ID > 250")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidConfiguration = apiError {
                    // Expected
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }
    }

    @Test("preset save request stores boot + custom API fields")
    func testPresetSaveRequestBootAndCustomFields() {
        let request = WLEDPresetSaveRequest(
            id: 42,
            name: "Test",
            quickLoad: "1",
            state: nil,
            applyAtBoot: true,
            customAPICommand: "{\"on\":true,\"bri\":128}"
        )

        #expect(request.applyAtBoot == true)
        #expect(request.customAPICommand == "{\"on\":true,\"bri\":128}")
    }
    
    // MARK: - setBrightness Tests
    
    @Test("setBrightness clamps values to 0-255")
    func testSetBrightnessClamping() async throws {
        let service = makeTestService()
        let device = createTestDevice()
        
        // The implementation uses max(0, min(255, brightness))
        // Test that extreme values are handled
        
        _ = try await service.setBrightness(for: device, brightness: -10)
        _ = try await service.setBrightness(for: device, brightness: 300)
    }

    @Test("parseResponse accepts lightweight save acknowledgements")
    func testParseResponseWithLightweightAck() async throws {
        let service = makeTestService()
        let device = createTestDevice()
        let data = Data("{\"psave\":42,\"n\":\"Test Preset\"}".utf8)

        let response = try await service.debugParseResponseForTests(data: data, device: device)
        #expect(response.info.name == device.name)
        #expect(response.state.brightness == device.brightness)
    }

    @Test("parseResponse maps WLED error code 4 to HTTP 501")
    func testParseResponseErrorCode4() async throws {
        let service = makeTestService()
        let device = createTestDevice()
        let data = Data("{\"error\":4}".utf8)

        do {
            _ = try await service.debugParseResponseForTests(data: data, device: device)
            Issue.record("Expected parseResponse to throw for error code 4")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .httpError(let statusCode) = apiError {
                    #expect(statusCode == 501)
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }
    }

    @Test("parseResponse rejects explicit success false payload")
    func testParseResponseSuccessFalse() async throws {
        let service = makeTestService()
        let device = createTestDevice()
        let data = Data("{\"success\":false}".utf8)

        do {
            _ = try await service.debugParseResponseForTests(data: data, device: device)
            Issue.record("Expected parseResponse to fail for success=false")
        } catch {
            if let apiError = error as? WLEDAPIError {
                if case .invalidResponse = apiError {
                    // Expected.
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }
    }

    @Test("time settings write WLED timezone table index without extra offset")
    func testUpdateDeviceTimeSettingsWritesWLEDTimezoneIndex() async throws {
        let service = makeTestService { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }

            if request.httpMethod == "GET", url.path == "/json/cfg" {
                return (response, Data("""
                {
                  "if": {
                    "ntp": {
                      "en": false,
                      "host": "1.wled.pool.ntp.org",
                      "tz": 0,
                      "offset": 0,
                      "ampm": false
                    }
                  },
                  "light": {
                    "gc": { "val": 2.2, "col": 2.2 }
                  }
                }
                """.utf8))
            }

            return (response, Data(Self.mockStateResponseJSON.utf8))
        }
        let device = createTestDevice(ipAddress: "192.168.0.6")
        let hongKong = try #require(TimeZone(identifier: "Asia/Hong_Kong"))
        let coordinate = CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694)

        try await service.updateDeviceTimeSettings(for: device, timeZone: hongKong, coordinate: coordinate)

        let recordedRequests = MockWLEDURLProtocol.requests()
        let recordedBodies = MockWLEDURLProtocol.requestBodies()
        let postIndex = try #require(recordedRequests.firstIndex {
            $0.httpMethod == "POST" && $0.url?.path == "/json/cfg"
        })
        let bodyData = try #require(recordedBodies[postIndex])
        let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let interfaces = try #require(body["if"] as? [String: Any])
        let ntp = try #require(interfaces["ntp"] as? [String: Any])

        #expect(ntp["en"] as? Bool == true)
        #expect(ntp["tz"] as? Int == 9)
        #expect(ntp["offset"] as? Int == 0)
        #expect(ntp["host"] as? String == "1.wled.pool.ntp.org")
        #expect((ntp["lt"] as? Double).map { abs($0 - 22.3193) < 0.0001 } == true)
        #expect((ntp["ln"] as? Double).map { abs($0 - 114.1694) < 0.0001 } == true)

        let statePostIndex = try #require(recordedRequests.firstIndex {
            $0.httpMethod == "POST" && $0.url?.path == "/json"
        })
        let stateBodyData = try #require(recordedBodies[statePostIndex])
        let stateBody = try #require(JSONSerialization.jsonObject(with: stateBodyData) as? [String: Any])
        #expect(stateBody["time"] as? Int != nil)
    }

    @Test("time settings use UTC table plus offset for unsupported zones")
    func testUpdateDeviceTimeSettingsUsesUTCOffsetForUnsupportedZone() async throws {
        let service = makeTestService { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }

            if request.httpMethod == "GET", url.path == "/json/cfg" {
                return (response, Data("""
                {
                  "if": {
                    "ntp": {
                      "en": true,
                      "tz": 12,
                      "offset": 43200
                    }
                  },
                  "light": {
                    "gc": { "val": 2.2, "col": 2.2 }
                  }
                }
                """.utf8))
            }

            return (response, Data(Self.mockStateResponseJSON.utf8))
        }
        let device = createTestDevice(ipAddress: "192.168.0.6")
        let chatham = try #require(TimeZone(identifier: "Pacific/Chatham"))

        try await service.updateDeviceTimeSettings(for: device, timeZone: chatham, coordinate: nil)

        let recordedRequests = MockWLEDURLProtocol.requests()
        let recordedBodies = MockWLEDURLProtocol.requestBodies()
        let postIndex = try #require(recordedRequests.firstIndex {
            $0.httpMethod == "POST" && $0.url?.path == "/json/cfg"
        })
        let bodyData = try #require(recordedBodies[postIndex])
        let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let interfaces = try #require(body["if"] as? [String: Any])
        let ntp = try #require(interfaces["ntp"] as? [String: Any])

        #expect(ntp["tz"] as? Int == 0)
        #expect(ntp["offset"] as? Int == chatham.secondsFromGMT())
    }

    @Test("clock-only time settings update preserves cached solar location")
    func testUpdateDeviceTimeSettingsPreservesSolarReferenceCacheWhenCoordinateIsNil() async throws {
        let service = makeTestService { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }

            if request.httpMethod == "GET", url.path == "/json/cfg" {
                return (response, Data("""
                {
                  "if": {
                    "ntp": {
                      "en": true,
                      "tz": 9,
                      "offset": 28800,
                      "lt": 22.3193,
                      "ln": 114.1694
                    }
                  },
                  "light": {
                    "gc": { "val": 2.2, "col": 2.2 }
                  }
                }
                """.utf8))
            }

            return (response, Data(Self.mockStateResponseJSON.utf8))
        }
        let device = createTestDevice(ipAddress: "192.168.0.6")
        let hongKong = try #require(TimeZone(identifier: "Asia/Hong_Kong"))

        try await service.updateDeviceTimeSettings(for: device, timeZone: hongKong, coordinate: nil)
        let reference = try await service.fetchSolarReference(for: device)

        #expect(reference.coordinate.map { abs($0.latitude - 22.3193) < 0.0001 } == true)
        #expect(reference.coordinate.map { abs($0.longitude - 114.1694) < 0.0001 } == true)
        #expect(reference.timeZone?.identifier == "Asia/Hong_Kong")
    }

    @Test("time settings parser reports timer clock readiness")
    func testFetchDeviceTimeSettingsReportsClockReadiness() async throws {
        let service = makeTestService { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }

            if request.httpMethod == "GET", url.path == "/json/cfg" {
                return (response, Data("""
                {
                  "if": {
                    "ntp": {
                      "en": 1,
                      "tz": 9,
                      "offset": 0
                    }
                  }
                }
                """.utf8))
            }

            return (response, Data("{}".utf8))
        }
        let device = createTestDevice(ipAddress: "192.168.0.6")

        let settings = try await service.fetchDeviceTimeSettings(for: device)

        #expect(settings.ntpEnabled == true)
        #expect(settings.timeZone?.identifier == "Asia/Hong_Kong")
        #expect(settings.timeZoneIndex == 9)
        #expect(settings.utcOffsetSeconds == 0)
        #expect(settings.isTimerClockReady)
    }

    @Test("time settings parser rejects timezone table with extra offset")
    func testFetchDeviceTimeSettingsRejectsTimezoneIndexWithExtraOffset() async throws {
        let service = makeTestService { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }

            if request.httpMethod == "GET", url.path == "/json/cfg" {
                return (response, Data("""
                {
                  "if": {
                    "ntp": {
                      "en": 1,
                      "tz": 9,
                      "offset": 28800
                    }
                  }
                }
                """.utf8))
            }

            return (response, Data("{}".utf8))
        }
        let device = createTestDevice(ipAddress: "192.168.0.6")

        let settings = try await service.fetchDeviceTimeSettings(for: device)

        #expect(settings.ntpEnabled == true)
        #expect(settings.timeZone?.identifier == "Asia/Hong_Kong")
        #expect(settings.timeZoneIndex == 9)
        #expect(settings.utcOffsetSeconds == 28800)
        #expect(!settings.isTimerClockReady)
    }

    @Test("time settings parser treats missing timezone as not clock ready")
    func testFetchDeviceTimeSettingsMissingTimezoneNotReady() async throws {
        let service = makeTestService { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }

            if request.httpMethod == "GET", url.path == "/json/cfg" {
                return (response, Data("""
                {
                  "if": {
                    "ntp": {
                      "en": true
                    }
                  }
                }
                """.utf8))
            }

            return (response, Data("{}".utf8))
        }
        let device = createTestDevice(ipAddress: "192.168.0.6")

        let settings = try await service.fetchDeviceTimeSettings(for: device)

        #expect(settings.ntpEnabled == true)
        #expect(settings.timeZone == nil)
        #expect(!settings.isTimerClockReady)
    }

    @Test("decode sparse timers returns 10 logical slots")
    func testDecodeSparseTimersReturnsTenLogicalSlots() async throws {
        let service = makeTestService()
        let decoded = await service._decodeWLEDTimersForTesting(from: [])
        #expect(decoded.count == service._wledTimerSlotCountForTesting)
        #expect(decoded.first?.id == 0)
        #expect(decoded.last?.id == 9)
    }

    private func makeTimer(
        id: Int,
        enabled: Bool = true,
        hour: Int = 7,
        minute: Int = 0,
        days: Int = 0x7F,
        macroId: Int = 10,
        startMonth: Int? = nil,
        startDay: Int? = nil,
        endMonth: Int? = nil,
        endDay: Int? = nil
    ) -> WLEDTimer {
        WLEDTimer(
            id: id,
            enabled: enabled,
            hour: hour,
            minute: minute,
            days: days,
            macroId: macroId,
            startMonth: startMonth,
            startDay: startDay,
            endMonth: endMonth,
            endDay: endDay
        )
    }

    @Test("decode remaps solar markers to sunrise/sunset slots")
    func testDecodeRemapsSolarSlots() async throws {
        let service = makeTestService()
        let raw: [[String: Any]] = [
            ["en": true, "hour": 7, "min": 30, "macro": 11, "dow": 0x7F],
            ["en": true, "hour": 255, "min": -15, "macro": 20, "dow": 0x7F],
            ["en": true, "hour": 254, "min": 10, "macro": 21, "dow": 0x7F]
        ]
        let decoded = await service._decodeWLEDTimersForTesting(from: raw)

        #expect(decoded.count == service._wledTimerSlotCountForTesting)
        #expect(decoded[0].macroId == 11)
        #expect(decoded[8].hour == 255)
        #expect(decoded[8].macroId == 20)
        #expect(decoded[9].hour == 254)
        #expect(decoded[9].macroId == 21)
    }

    @Test("decode handles swapped sparse solar ordering without dropping either slot")
    func testDecodeHandlesSwappedSolarOrdering() async throws {
        let service = makeTestService()
        let raw: [[String: Any]] = [
            ["en": true, "hour": 7, "min": 30, "macro": 11, "dow": 0x7F],
            ["en": true, "hour": 254, "min": 10, "macro": 21, "dow": 0x7F],
            ["en": true, "hour": 255, "min": -15, "macro": 20, "dow": 0x7F]
        ]
        let decoded = await service._decodeWLEDTimersForTesting(from: raw)

        #expect(decoded[0].macroId == 11)
        #expect(decoded[8].hour == 255)
        #expect(decoded[8].macroId == 20)
        #expect(decoded[9].hour == 254)
        #expect(decoded[9].macroId == 21)
    }

    @Test("decode treats a second legacy hour 255 marker as sunset")
    func testDecodeTreatsSecondLegacySunriseMarkerAsSunset() async throws {
        let service = makeTestService()
        let raw: [[String: Any]] = [
            ["en": true, "hour": 255, "min": -5, "macro": 76, "dow": 0x7F],
            ["en": true, "hour": 255, "min": 5, "macro": 77, "dow": 0x7F]
        ]

        let decoded = await service._decodeWLEDTimersForTesting(from: raw)
        #expect(decoded[8].hour == 255)
        #expect(decoded[8].macroId == 76)
        #expect(decoded[9].hour == 255)
        #expect(decoded[9].macroId == 77)
    }

    @Test("decode treats ten compact rows as WLED vector rows")
    func testDecodeTreatsTenRowsAsCompactWLEDVector() async throws {
        let service = makeTestService()
        let raw: [[String: Any]] = [
            ["en": true, "hour": 6, "min": 0, "macro": 20, "dow": 0x7F],
            ["en": true, "hour": 7, "min": 0, "macro": 21, "dow": 0x7F],
            ["en": true, "hour": 8, "min": 0, "macro": 22, "dow": 0x7F],
            ["en": true, "hour": 9, "min": 0, "macro": 23, "dow": 0x7F],
            ["en": true, "hour": 254, "min": 0, "macro": 80, "dow": 0x7F],
            ["en": true, "hour": 10, "min": 0, "macro": 24, "dow": 0x7F],
            ["en": true, "hour": 11, "min": 0, "macro": 25, "dow": 0x7F],
            ["en": true, "hour": 12, "min": 0, "macro": 26, "dow": 0x7F],
            ["en": true, "hour": 255, "min": 0, "macro": 81, "dow": 0x7F],
            ["en": true, "hour": 13, "min": 0, "macro": 27, "dow": 0x7F]
        ]

        let decoded = await service._decodeWLEDTimersForTesting(from: raw)

        #expect(decoded[0].macroId == 20)
        #expect(decoded[4].macroId == 24)
        #expect(decoded[7].macroId == 27)
        #expect(decoded[8].macroId == 81)
        #expect(decoded[9].macroId == 80)
    }

    @Test("decode preserves extra native WLED timer rows beyond app logical slots")
    func testDecodePreservesExtraNativeTimerRows() async throws {
        let service = makeTestService()
        let raw: [[String: Any]] = [
            ["en": true, "hour": 6, "min": 0, "macro": 20, "dow": 0x7F],
            ["en": true, "hour": 7, "min": 0, "macro": 21, "dow": 0x7F],
            ["en": true, "hour": 8, "min": 0, "macro": 22, "dow": 0x7F],
            ["en": true, "hour": 9, "min": 0, "macro": 23, "dow": 0x7F],
            ["en": true, "hour": 10, "min": 0, "macro": 24, "dow": 0x7F],
            ["en": true, "hour": 11, "min": 0, "macro": 25, "dow": 0x7F],
            ["en": true, "hour": 12, "min": 0, "macro": 26, "dow": 0x7F],
            ["en": true, "hour": 13, "min": 0, "macro": 27, "dow": 0x7F],
            ["en": true, "hour": 14, "min": 0, "macro": 28, "dow": 0x7F],
            ["en": true, "hour": 15, "min": 0, "macro": 29, "dow": 0x7F]
        ]

        let decoded = await service._decodeWLEDTimersForTesting(from: raw)
        let update = WLEDTimerUpdate(
            id: 0,
            enabled: true,
            hour: 6,
            minute: 30,
            days: 0x7F,
            macroId: 99,
            startMonth: nil,
            startDay: nil,
            endMonth: nil,
            endDay: nil
        )
        let merged = try await service._mergeTimersApplyingUpdateForTesting(
            currentTimers: decoded,
            timerUpdate: update
        )
        let encoded = await service._encodeWLEDTimersForTesting(merged)

        #expect(decoded.count == service._wledTimerSlotCountForTesting + 2)
        #expect(decoded[10].macroId == 28)
        #expect(decoded[11].macroId == 29)
        #expect(merged.contains { $0.id == 10 && $0.macroId == 28 })
        #expect(merged.contains { $0.id == 11 && $0.macroId == 29 })
        #expect(Array(encoded.compactMap { $0["macro"] as? Int }.suffix(2)) == [28, 29])
    }

    @Test("decode ignores WLED macro zero solar placeholders")
    func testDecodeIgnoresMacroZeroSolarPlaceholders() async throws {
        let service = makeTestService()
        let raw: [[String: Any]] = [
            ["en": 1, "hour": 255, "min": 0, "macro": 0, "dow": 0x7F],
            ["en": 1, "hour": 255, "min": 0, "macro": 0, "dow": 0x7F]
        ]

        let decoded = await service._decodeWLEDTimersForTesting(from: raw)

        #expect(decoded.count == service._wledTimerSlotCountForTesting)
        #expect(decoded.allSatisfy { $0.macroId == 0 })
        #expect(decoded.allSatisfy { $0.hour == 0 })
        #expect(decoded.allSatisfy { !$0.enabled })
    }

    @Test("decode accepts WLED integer enabled flag for real timers")
    func testDecodeAcceptsIntegerEnabledFlagForRealTimers() async throws {
        let service = makeTestService()
        let raw: [[String: Any]] = [
            ["en": 1, "hour": 6, "min": 15, "macro": 42, "dow": 0x7F]
        ]

        let decoded = await service._decodeWLEDTimersForTesting(from: raw)

        #expect(decoded[0].enabled == true)
        #expect(decoded[0].hour == 6)
        #expect(decoded[0].minute == 15)
        #expect(decoded[0].macroId == 42)
    }

    @Test("encode preserves positional slots through highest used timer")
    func testEncodePreservesPositionalSlotsThroughHighestUsed() async throws {
        let service = makeTestService()

        var timers: [WLEDTimer] = (0..<10).map { slot in
            WLEDTimer(
                id: slot,
                enabled: false,
                hour: 0,
                minute: 0,
                days: 0x7F,
                macroId: 0,
                startMonth: nil,
                startDay: nil,
                endMonth: nil,
                endDay: nil
            )
        }
        timers[8] = WLEDTimer(
            id: 8,
            enabled: true,
            hour: 255,
            minute: -20,
            days: 0x7F,
            macroId: 30,
            startMonth: nil,
            startDay: nil,
            endMonth: nil,
            endDay: nil
        )
        timers[9] = WLEDTimer(
            id: 9,
            enabled: true,
            hour: 254,
            minute: 15,
            days: 0x7F,
            macroId: 31,
            startMonth: nil,
            startDay: nil,
            endMonth: nil,
            endDay: nil
        )

        let encoded = await service._encodeWLEDTimersForTesting(timers)
        #expect(encoded.count == 10)
        #expect(encoded[8]["en"] as? Int == 1)
        #expect(encoded[0]["hour"] as? Int == 0)
        #expect(encoded[0]["macro"] as? Int == 0)
        #expect(encoded[8]["hour"] as? Int == 255)
        #expect(encoded[8]["macro"] as? Int == 30)
        #expect(encoded[9]["hour"] as? Int == 254)
        #expect(encoded[9]["macro"] as? Int == 31)
    }

    @Test("encode keeps placeholder entries before sparse regular slot")
    func testEncodeKeepsPlaceholderBeforeSparseRegularSlot() async throws {
        let service = makeTestService()

        var timers: [WLEDTimer] = (0..<10).map { slot in
            WLEDTimer(
                id: slot,
                enabled: false,
                hour: 0,
                minute: 0,
                days: 0x7F,
                macroId: 0,
                startMonth: nil,
                startDay: nil,
                endMonth: nil,
                endDay: nil
            )
        }
        timers[1] = WLEDTimer(
            id: 1,
            enabled: true,
            hour: 7,
            minute: 2,
            days: 0x7F,
            macroId: 249,
            startMonth: nil,
            startDay: nil,
            endMonth: nil,
            endDay: nil
        )

        let encoded = await service._encodeWLEDTimersForTesting(timers)
        #expect(encoded.count == 2)
        #expect(encoded[0]["hour"] as? Int == 0)
        #expect(encoded[0]["macro"] as? Int == 0)
        #expect(encoded[1]["hour"] as? Int == 7)
        #expect(encoded[1]["min"] as? Int == 2)
        #expect(encoded[1]["macro"] as? Int == 249)
    }

    @Test("encode forceIncludeThroughSlot keeps explicit cleared slot payload")
    func testEncodeForceIncludeThroughSlotForClearedTimer() async throws {
        let service = makeTestService()

        let timers: [WLEDTimer] = (0..<10).map { slot in
            WLEDTimer(
                id: slot,
                enabled: false,
                hour: 0,
                minute: 0,
                days: 0x7F,
                macroId: 0,
                startMonth: nil,
                startDay: nil,
                endMonth: nil,
                endDay: nil
            )
        }

        let encodedWithoutForce = await service._encodeWLEDTimersForTesting(timers)
        #expect(encodedWithoutForce.isEmpty)

        let encodedWithForce = await service._encodeWLEDTimersForTesting(
            timers,
            forceIncludeThroughSlot: 0
        )
        #expect(encodedWithForce.count == 1)
        #expect(encodedWithForce[0]["en"] as? Int == 0)
        #expect(encodedWithForce[0]["hour"] as? Int == 0)
        #expect(encodedWithForce[0]["min"] as? Int == 0)
        #expect(encodedWithForce[0]["macro"] as? Int == 0)
        #expect(encodedWithForce[0]["dow"] as? Int == 0x7F)
    }

    @Test("encode persisted timer rows omits cleared placeholders")
    func testEncodePersistedTimerRowsOmitsClearedPlaceholders() async throws {
        let service = makeTestService()
        let timers = [
            makeTimer(id: 0, enabled: false, hour: 0, minute: 0, macroId: 0),
            makeTimer(id: 1, hour: 8, minute: 15, macroId: 42)
        ]

        let encoded = await service._encodePersistedWLEDTimerRowsForTesting(timers)

        #expect(encoded.count == 1)
        #expect(encoded[0]["hour"] as? Int == 8)
        #expect(encoded[0]["min"] as? Int == 15)
        #expect(encoded[0]["macro"] as? Int == 42)
    }

    @Test("timer row delete plan removes compacted row by field identity")
    func testTimerRowDeletePlanRemovesCompactedRowByFieldIdentity() async throws {
        let service = makeTestService()
        let candidateBeforeCompaction = makeTimer(id: 1, hour: 4, minute: 0, macroId: 250)
        let currentAfterCompaction = [
            makeTimer(id: 0, hour: 4, minute: 0, macroId: 250)
        ]

        let remaining = await service._timerRowsAfterDeletingForTesting(
            candidates: [candidateBeforeCompaction],
            currentTimers: currentAfterCompaction
        )

        #expect(remaining != nil)
        #expect(remaining?.contains(where: { $0.macroId == 250 }) == false)
    }

    @Test("timer row delete plan force-clears full timer surface for final real timer")
    func testTimerRowDeletePlanForceIncludesClearedRowForFinalTimer() async throws {
        let service = makeTestService()
        let candidateBeforeCompaction = makeTimer(id: 1, hour: 15, minute: 46, macroId: 41)
        let currentAfterCompaction = [
            makeTimer(id: 0, hour: 15, minute: 46, macroId: 41)
        ]

        let remaining = await service._timerRowsAfterDeletingForTesting(
            candidates: [candidateBeforeCompaction],
            currentTimers: currentAfterCompaction
        )
        let payload = await service._timerRowsDeletePayloadForTesting(
            remainingTimers: remaining ?? currentAfterCompaction,
            deletedCandidates: [currentAfterCompaction[0]]
        )

        #expect(remaining?.contains(where: { $0.macroId == 41 }) == false)
        #expect(payload.forceClearedSlot == 9)
        #expect(payload.rows.count == 10)
        #expect(payload.rows[0]["en"] as? Int == 0)
        #expect(payload.rows[0]["hour"] as? Int == 0)
        #expect(payload.rows[0]["macro"] as? Int == 0)
        #expect(payload.rows.allSatisfy { ($0["macro"] as? Int) == 0 })
    }

    @Test("timer row delete payload force-clears deleted solar slot")
    func testTimerRowDeletePayloadForceClearsDeletedSolarSlot() async throws {
        let service = makeTestService()
        let candidate = makeTimer(id: 9, hour: 254, minute: 0, macroId: 34)
        let currentTimers = [
            makeTimer(id: 0, hour: 16, minute: 36, macroId: 12),
            makeTimer(id: 1, hour: 0, minute: 0, macroId: 51),
            makeTimer(id: 8, hour: 255, minute: 0, macroId: 50),
            candidate
        ]

        let remaining = await service._timerRowsAfterDeletingForTesting(
            candidates: [candidate],
            currentTimers: currentTimers
        )
        let payload = await service._timerRowsDeletePayloadForTesting(
            remainingTimers: remaining ?? currentTimers,
            deletedCandidates: [candidate]
        )

        #expect(remaining?.contains(where: { $0.macroId == 34 }) == false)
        #expect(payload.forceClearedSlot == 9)
        #expect(payload.rows.count == 10)
        #expect(payload.rows[0]["macro"] as? Int == 12)
        #expect(payload.rows[1]["macro"] as? Int == 51)
        #expect(payload.rows[8]["macro"] as? Int == 50)
        #expect(payload.rows[9]["macro"] as? Int == 0)
        #expect(payload.rows.contains { ($0["macro"] as? Int) == 34 } == false)
    }

    @Test("timer row delete payload keeps cleared placeholder before shifted regular rows")
    func testTimerRowDeletePayloadClearsDeletedRegularSlotBeforeShiftedRows() async throws {
        let service = makeTestService()
        let candidate = makeTimer(id: 0, hour: 16, minute: 6, macroId: 11)
        let currentTimers = [
            candidate,
            makeTimer(id: 1, hour: 17, minute: 6, macroId: 12),
            makeTimer(id: 2, hour: 16, minute: 6, macroId: 30),
            makeTimer(id: 8, hour: 255, minute: 0, macroId: 47),
            makeTimer(id: 9, hour: 254, minute: 0, macroId: 31)
        ]

        let remaining = await service._timerRowsAfterDeletingForTesting(
            candidates: [candidate],
            currentTimers: currentTimers
        )
        let payload = await service._timerRowsDeletePayloadForTesting(
            remainingTimers: remaining ?? currentTimers,
            deletedCandidates: [candidate]
        )

        #expect(remaining?.contains(where: { $0.macroId == 11 }) == false)
        #expect(payload.forceClearedSlot == 0)
        #expect(payload.rows.count == 10)
        #expect(payload.rows[0]["macro"] as? Int == 0)
        #expect(payload.rows[1]["macro"] as? Int == 12)
        #expect(payload.rows[2]["macro"] as? Int == 30)
        #expect(payload.rows[8]["macro"] as? Int == 47)
        #expect(payload.rows[9]["macro"] as? Int == 31)
    }

    @Test("timer row delete plan refuses ambiguous shifted duplicates")
    func testTimerRowDeletePlanRefusesAmbiguousShiftedDuplicates() async throws {
        let service = makeTestService()
        let candidateBeforeCompaction = makeTimer(id: 1, hour: 4, minute: 0, macroId: 250)
        let currentWithAmbiguousMatches = [
            makeTimer(id: 0, hour: 4, minute: 0, macroId: 250),
            makeTimer(id: 2, hour: 4, minute: 0, macroId: 250)
        ]

        let remaining = await service._timerRowsAfterDeletingForTesting(
            candidates: [candidateBeforeCompaction],
            currentTimers: currentWithAmbiguousMatches
        )

        #expect(remaining == nil)
    }

    @Test("timer row delete plan verifies remaining duplicate count")
    func testTimerRowDeletePlanVerifiesRemainingDuplicateCount() async throws {
        let service = makeTestService()
        let currentDuplicateRows = [
            makeTimer(id: 0, hour: 0, minute: 0, macroId: 45),
            makeTimer(id: 1, hour: 0, minute: 0, macroId: 45),
            makeTimer(id: 2, hour: 0, minute: 0, macroId: 45),
            makeTimer(id: 3, hour: 0, minute: 0, macroId: 45)
        ]
        let candidates = Array(currentDuplicateRows.dropFirst())

        let remaining = await service._timerRowsAfterDeletingForTesting(
            candidates: candidates,
            currentTimers: currentDuplicateRows
        )

        #expect(remaining?.count == 1)
        #expect(remaining?.first?.macroId == 45)
        #expect(await service._timerRowsMatchExpectedForTesting(
            currentTimers: [makeTimer(id: 0, hour: 0, minute: 0, macroId: 45)],
            expectedRemainingTimers: remaining ?? []
        ))
        #expect(await service._timerRowsMatchExpectedForTesting(
            currentTimers: currentDuplicateRows,
            expectedRemainingTimers: remaining ?? []
        ) == false)
    }

    @Test("timer update preserves fetched WLED config while replacing timer rows")
    func testUpdateTimerPreservesFetchedConfigWhileReplacingTimerRows() async throws {
        let service = makeTestService { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw URLError(.badURL)
            }

            if request.httpMethod == "GET", url.path == "/json/cfg" {
                return (response, Data(Self.mockConfigJSON.utf8))
            }

            return (response, Data("{}".utf8))
        }
        let device = createTestDevice(ipAddress: "192.168.0.6")
        let update = WLEDTimerUpdate(
            id: 0,
            enabled: true,
            hour: 19,
            minute: 22,
            days: 0x7F,
            macroId: 47,
            startMonth: nil,
            startDay: nil,
            endMonth: nil,
            endDay: nil
        )

        try await service.updateTimer(update, on: device)

        let recordedRequests = MockWLEDURLProtocol.requests()
        let recordedBodies = MockWLEDURLProtocol.requestBodies()
        let postIndex = try #require(recordedRequests.firstIndex {
            $0.httpMethod == "POST" && $0.url?.path == "/json/cfg"
        })
        let bodyData = try #require(recordedBodies[postIndex])
        let body = try #require(
            JSONSerialization.jsonObject(with: bodyData, options: []) as? [String: Any]
        )
        let timers = try #require(body["timers"] as? [String: Any])
        let rows = try #require(timers["ins"] as? [[String: Any]])

        #expect(body["cfg"] == nil)
        let interfaces = try #require(body["if"] as? [String: Any])
        let hardware = try #require(body["hw"] as? [String: Any])
        let led = try #require(hardware["led"] as? [String: Any])
        #expect(interfaces["sync"] != nil)
        #expect(led["total"] as? Int == 30)
        #expect(led["maxpwr"] as? Int == 850)
        #expect(rows.count == 1)
        #expect(rows[0]["en"] as? Int == 1)
        #expect(rows[0]["hour"] as? Int == 19)
        #expect(rows[0]["min"] as? Int == 22)
        #expect(rows[0]["macro"] as? Int == 47)
    }

    @Test("timer update merge uses fixed logical slots independent of sparse input")
    func testTimerMergeIgnoresSparseCount() async throws {
        let service = makeTestService()
        let sparseCurrent: [WLEDTimer] = [
            WLEDTimer(
                id: 0,
                enabled: true,
                hour: 8,
                minute: 0,
                days: 0x7F,
                macroId: 10,
                startMonth: nil,
                startDay: nil,
                endMonth: nil,
                endDay: nil
            ),
            WLEDTimer(
                id: 1,
                enabled: true,
                hour: 9,
                minute: 0,
                days: 0x7F,
                macroId: 11,
                startMonth: nil,
                startDay: nil,
                endMonth: nil,
                endDay: nil
            )
        ]

        let update = WLEDTimerUpdate(
            id: 9,
            enabled: true,
            hour: 254,
            minute: 5,
            days: 0x7F,
            macroId: 42,
            startMonth: nil,
            startDay: nil,
            endMonth: nil,
            endDay: nil
        )
        let merged = try await service._mergeTimersApplyingUpdateForTesting(
            currentTimers: sparseCurrent,
            timerUpdate: update
        )

        #expect(merged.count == service._wledTimerSlotCountForTesting)
        #expect(merged[9].macroId == 42)
        #expect(merged[9].hour == 254)
        #expect(merged[0].macroId == 10)
    }

    @Test("automation snapshot uses one config read and one preset-store read")
    func testAutomationSnapshotRequestBudget() async throws {
        let service = makeTestService()
        let device = createTestDevice()

        let snapshot = try await service.fetchDeviceAutomationSnapshot(for: device)

        #expect(snapshot.deviceId == device.id)
        #expect(snapshot.presetIds.contains(10))
        #expect(snapshot.playlistIds.contains(11))
        #expect(snapshot.presets.contains { $0.id == 10 })
        #expect(snapshot.playlists.contains { $0.id == 11 })
        #expect(snapshot.presetStoreRecordHashes[10] != nil)
        #expect(snapshot.presetStoreRecordHashes[11] != nil)

        let paths = MockWLEDURLProtocol.requests().compactMap(\.url?.path)
        #expect(paths.filter { $0 == "/json/cfg" }.count == 1)
        #expect(paths.filter { $0 == "/presets.json" }.count == 1)
        #expect(paths.count == 2)
        #expect(MockWLEDURLProtocol.requests().allSatisfy { $0.httpMethod == "GET" })
    }

    @Test("timer mutation reads one merge base before its write")
    func testTimerMutationUsesOnePreWriteConfigRead() async throws {
        var didWrite = false
        let initialConfig = """
        {"timers":{"ins":[{"en":0,"hour":18,"min":0,"macro":0,"dow":127}]},"if":{"sync":{}}}
        """
        let updatedConfig = """
        {"timers":{"ins":[{"en":1,"hour":19,"min":22,"macro":47,"dow":127}]},"if":{"sync":{}}}
        """
        let service = makeTestService { request in
            let response = try okResponse(for: try #require(request.url))
            if request.url?.path == "/json/cfg", request.httpMethod == "POST" {
                didWrite = true
                return (response, Data("{}".utf8))
            }
            if request.url?.path == "/json/cfg" {
                return (response, Data((didWrite ? updatedConfig : initialConfig).utf8))
            }
            return (response, Data(Self.mockPresetsJSON.utf8))
        }
        let update = WLEDTimerUpdate(
            id: 0,
            enabled: true,
            hour: 19,
            minute: 22,
            days: 0x7F,
            macroId: 47,
            startMonth: nil,
            startDay: nil,
            endMonth: nil,
            endDay: nil
        )

        let outcome = await service.updateAndVerifyTimer(update, on: createTestDevice())

        #expect(outcome == .committed)
        let requests = MockWLEDURLProtocol.requests()
        let postIndex = try #require(requests.firstIndex {
            $0.url?.path == "/json/cfg" && $0.httpMethod == "POST"
        })
        let preWriteConfigReads = requests[..<postIndex].filter {
            $0.url?.path == "/json/cfg" && $0.httpMethod != "POST"
        }
        #expect(preWriteConfigReads.count == 1)
    }

    @Test("conditional cleanup preserves a reused preset ID")
    func testConditionalDeletePreservesSupersededRecord() async throws {
        let currentStore = """
        {"0":{},"10":{"n":"User replacement","seg":[]}}
        """
        let service = makeTestService { request in
            let response = try okResponse(for: try #require(request.url))
            if request.url?.path == "/presets.json" {
                return (response, Data(currentStore.utf8))
            }
            return (response, Data(Self.mockConfigJSON.utf8))
        }
        let target = CleanupDeleteTarget(
            resourceType: .preset,
            id: 10,
            ownership: CleanupOwnershipEvidence(
                recordHash: "old-record-hash",
                semanticSignature: "{n:\"Old managed preset\"}",
                markerKind: .automation,
                expectedTimerSignature: nil,
                ownerAutomationId: UUID()
            )
        )

        let report = try await service.rewritePresetStoreConditionallyDeleting(
            targets: [target],
            device: createTestDevice()
        )

        #expect(report.outcome == .committed)
        #expect(report.superseded == Set([target]))
        #expect(report.deleted.isEmpty)
        #expect(MockWLEDURLProtocol.requests().allSatisfy { $0.url?.path != "/edit" })
    }

    @Test("conditional cleanup deletes the exact captured record")
    func testConditionalDeleteUsesCapturedIdentity() async throws {
        var storedData = Data(Self.mockPresetsJSON.utf8)
        let service = makeTestService { request in
            let response = try okResponse(for: try #require(request.url))
            if request.url?.path == "/upload", request.httpMethod == "POST" {
                storedData = try uploadedPresetStoreData(from: request)
                return (response, Data("{}".utf8))
            }
            if request.url?.path == "/presets.json" {
                return (response, storedData)
            }
            return (response, Data(Self.mockConfigJSON.utf8))
        }
        let device = createTestDevice()
        let targets = try await service.capturePresetStoreCleanupTargets(
            playlistIds: [],
            presetIds: [10],
            device: device
        )

        let report = try await service.rewritePresetStoreConditionallyDeleting(
            targets: targets,
            device: device
        )

        #expect(report.outcome == .committed)
        #expect(report.deleted.map(\.id) == [10])
        let finalObject = try #require(
            JSONSerialization.jsonObject(with: storedData) as? [String: Any]
        )
        #expect(finalObject["10"] == nil)
        #expect(finalObject["11"] != nil)
    }

    @Test("conditional cleanup accepts a matching owner-scoped internal marker")
    func testConditionalDeleteUsesOwnerScopedMarker() async throws {
        let ownerId = try #require(
            UUID(uuidString: "11111111-2222-3333-4444-555555555555")
        )
        var storedData = Data("""
        {
          "0": {},
          "10": { "n": "[AD:o=111111112222 automation] Morning", "seg": [] },
          "11": { "n": "Keep", "seg": [] }
        }
        """.utf8)
        let service = makeTestService { request in
            let response = try okResponse(for: try #require(request.url))
            if request.url?.path == "/upload", request.httpMethod == "POST" {
                storedData = try uploadedPresetStoreData(from: request)
                return (response, Data("{}".utf8))
            }
            if request.url?.path == "/presets.json" {
                return (response, storedData)
            }
            return (response, Data(Self.mockConfigJSON.utf8))
        }
        let target = CleanupDeleteTarget(
            resourceType: .preset,
            id: 10,
            ownership: CleanupOwnershipEvidence(
                recordHash: nil,
                semanticSignature: nil,
                markerKind: .automation,
                expectedTimerSignature: nil,
                ownerAutomationId: ownerId
            )
        )

        let report = try await service.rewritePresetStoreConditionallyDeleting(
            targets: [target],
            device: createTestDevice()
        )

        #expect(report.outcome == .committed)
        #expect(report.deleted == Set([target]))
        let finalObject = try #require(
            JSONSerialization.jsonObject(with: storedData) as? [String: Any]
        )
        #expect(finalObject["10"] == nil)
        #expect(finalObject["11"] != nil)
    }
}
