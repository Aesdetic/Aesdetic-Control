import Foundation

private final class WLEDAdvancedSettingsBundleToken {}

enum WLEDAdvancedSettingsError: LocalizedError, Equatable {
    case ledOutputVerificationFailed(String)
    case usermodVerificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .ledOutputVerificationFailed(let reason):
            return reason
        case .usermodVerificationFailed(let reason):
            return reason
        }
    }
}

actor WLEDAdvancedSettingsService {
    static let shared = WLEDAdvancedSettingsService()

    private let urlSession: URLSession
    private var cachedManifest: WLEDSettingsManifest?

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func loadManifest() throws -> WLEDSettingsManifest {
        if let cachedManifest {
            return cachedManifest
        }

        guard let url = Self.manifestURL() else {
            throw WLEDAPIError.invalidConfiguration
        }

        do {
            let data = try Data(contentsOf: url)
            let manifest = try JSONDecoder().decode(WLEDSettingsManifest.self, from: data)
            cachedManifest = manifest
            return manifest
        } catch let apiError as WLEDAPIError {
            throw apiError
        } catch let decodingError as DecodingError {
            throw WLEDAPIError.decodingError(decodingError)
        } catch {
            throw WLEDAPIError.networkError(error)
        }
    }

    private static func manifestURL() -> URL? {
        let bundles = [Bundle.main, Bundle(for: WLEDAdvancedSettingsBundleToken.self)]
            + Bundle.allBundles
            + Bundle.allFrameworks
        for bundle in bundles {
            if let url = bundle.url(forResource: "WLEDSettingsManifest", withExtension: "json") {
                return url
            }
        }
        return nil
    }

    func fetchDraft(categoryID: String, for device: WLEDDevice) async throws -> WLEDSettingsDraft {
        let manifest = try loadManifest()
        guard let category = manifest.category(id: categoryID) else {
            throw WLEDAPIError.invalidConfiguration
        }

        let rawConfig = try await fetchRawConfig(for: device)
        let config = resolvedConfigRoot(rawConfig)
        var values: [String: WLEDSettingValue] = [:]
        var secretStates: [String: WLEDSecretDraftState] = [:]

        for field in category.fields {
            if field.secret {
                secretStates[field.key] = .preserve(configured: secretConfigured(field: field, in: config))
                values[field.key] = .string("")
                continue
            }

            if let path = field.configPath, !path.contains("*") {
                values[field.key] = coerceValue(
                    WLEDSettingValue.fromJSON(resolve(path: path, in: config)),
                    for: field,
                    config: config
                )
            } else {
                values[field.key] = .null
            }
        }

        return WLEDSettingsDraft(
            category: category,
            originalValues: values,
            values: values,
            secretStates: secretStates
        )
    }

    func fetchSupportedAdvancedFeatures(for device: WLEDDevice) async throws -> Set<String> {
        let root = resolvedConfigRoot(try await fetchRawConfig(for: device))
        let info = try? await fetchRawInfo(for: device)
        var features: Set<String> = []

        if root["dmx"] is [String: Any] {
            features.insert("WLED_ENABLE_DMX")
        }

        let network = root["nw"] as? [String: Any]
        let interface = root["if"] as? [String: Any]
        let sync = interface?["sync"] as? [String: Any]
        if network?["espnow"] != nil || sync?["espnow"] != nil {
            features.insert("WLED_ENABLE_ESPNOW")
        }

        let live = interface?["live"] as? [String: Any]
        let liveDMX = live?["dmx"] as? [String: Any]
        if liveDMX?["inputRxPin"] != nil
            || liveDMX?["inputTxPin"] != nil
            || liveDMX?["inputEnablePin"] != nil
            || liveDMX?["dmxInputPort"] != nil {
            features.insert("WLED_ENABLE_DMX_INPUT")
        }

        let leds = info?["leds"] as? [String: Any]
        let segmentCapabilities = (leds?["seglc"] as? [Any])?.compactMap { value -> Int? in
            if let number = value as? NSNumber { return number.intValue }
            return value as? Int
        } ?? []
        let reportsCCT = (leds?["cct"] as? Bool) == true
            || segmentCapabilities.contains { ($0 & 0b100) != 0 }
        if reportsCCT {
            features.insert("WLED_ENABLE_CCT_OUTPUT")
        }

        return features
    }

    private func fetchSettingsPage(_ path: String, for device: WLEDDevice) async throws -> String {
        guard let url = URL(string: "http://\(device.ipAddress)\(path)") else {
            throw WLEDAPIError.invalidURL
        }

        do {
            let (data, response) = try await urlSession.data(from: url)
            try validateHTTPResponse(response)
            return String(data: data, encoding: .utf8) ?? ""
        } catch let apiError as WLEDAPIError {
            throw apiError
        } catch {
            throw WLEDAPIError.networkError(error)
        }
    }

    func saveDraft(_ draft: WLEDSettingsDraft, for device: WLEDDevice) async throws -> WLEDSettingsSaveResult {
        let errors = draft.validationErrors()
        guard errors.isEmpty else {
            throw WLEDAPIError.invalidConfiguration
        }

        let changedFields = draft.changedFields
        let writableChangedFields = changedFields.filter(\.isWritableByGenericConfig)
        let actionOnlyChangedFields = actionOnlyFields(in: draft, fields: changedFields)
        let configWritableChangedFields = writableChangedFields.filter { field in
            !actionOnlyChangedFields.contains(where: { $0.key == field.key })
        }
        let wifiSecretFields = verifiedWiFiSecretFields(in: draft, fields: changedFields)
        let syncSecretFields = verifiedSyncSecretFields(in: draft, fields: changedFields)
        let securitySecretFields = verifiedSecuritySecretFields(in: draft, fields: changedFields)
        guard !configWritableChangedFields.isEmpty || !actionOnlyChangedFields.isEmpty || !wifiSecretFields.isEmpty || !syncSecretFields.isEmpty || !securitySecretFields.isEmpty else {
            return WLEDSettingsSaveResult(
                savedKeys: [],
                sideEffects: draft.sideEffects,
                requiresRefresh: false
            )
        }

        var rawConfig = try await fetchRawConfig(for: device)
        var root = resolvedConfigRoot(rawConfig)

        for field in configWritableChangedFields {
            guard let path = field.configPath, let value = draft.values[field.key] else { continue }
            let encoded = encodeValue(value, field: field, draft: draft)
            set(encoded, at: path, in: &root)
        }

        if rawConfig["cfg"] is [String: Any] {
            rawConfig["cfg"] = root
        } else {
            rawConfig = root
        }

        if needsUsermodsSettingsFormSave(for: draft.category, fields: configWritableChangedFields + actionOnlyChangedFields) {
            try await postUsermodsSettingsForm(root, draft: draft, for: device)
        } else if needsDMXOutputSettingsFormSave(for: draft.category, fields: configWritableChangedFields) {
            try await postDMXOutputSettingsForm(root, for: device)
        } else if needsWiFiSettingsFormSave(for: draft.category, fields: configWritableChangedFields + wifiSecretFields) {
            try await postWiFiSettingsForm(
                root,
                for: device,
                secretOverrides: wifiSecretOverrides(from: draft, fields: wifiSecretFields)
            )
        } else if needsSyncSettingsFormSave(for: draft.category, fields: configWritableChangedFields + syncSecretFields) {
            try await postSyncSettingsForm(
                root,
                for: device,
                secretOverrides: syncSecretOverrides(from: draft, fields: syncSecretFields)
            )
        } else if needsSecuritySettingsFormSave(for: draft.category, fields: configWritableChangedFields + securitySecretFields) {
            try await postSecuritySettingsForm(
                root,
                for: device,
                secretOverrides: securitySecretOverrides(from: draft, fields: securitySecretFields)
            )
        } else if needsTimeSettingsFormSave(for: draft.category, fields: configWritableChangedFields) {
            try await postTimeSettingsForm(root, for: device)
        } else if needsLEDSettingsFormSave(for: configWritableChangedFields) {
            try await postLEDSettingsForm(root, for: device)
        } else {
            try await postRawConfig(rawConfig, for: device)
        }
        try await verifySavedFields(configWritableChangedFields, from: draft, for: device)

        return WLEDSettingsSaveResult(
            savedKeys: Set((configWritableChangedFields + actionOnlyChangedFields + wifiSecretFields + syncSecretFields + securitySecretFields).map(\.key)),
            sideEffects: draft.sideEffects,
            requiresRefresh: draft.sideEffects.contains(.wifiReconnect)
                || draft.sideEffects.contains(.reboot)
                || draft.sideEffects.contains(.ledReinit)
                || draft.sideEffects.contains(.segmentRebuild)
        )
    }

    func fetchLEDOutputDraft(for device: WLEDDevice) async throws -> WLEDLEDOutputDraft {
        let root = resolvedConfigRoot(try await fetchRawConfig(for: device))
        let outputs = ledOutputs(from: root)
        let resolvedOutputs = outputs.isEmpty ? [defaultLEDOutput()] : outputs
        let colorOverrides = colorOrderOverrides(from: root)
        return WLEDLEDOutputDraft(
            originalOutputs: resolvedOutputs,
            originalColorOverrides: colorOverrides,
            diagnostics: ledDiagnostics(from: root, outputs: resolvedOutputs),
            outputs: resolvedOutputs,
            colorOverrides: colorOverrides
        )
    }

    func fetchPinInfo(for device: WLEDDevice) async throws -> WLEDPinInfo {
        guard let url = URL(string: "http://\(device.ipAddress)/json/pins") else {
            throw WLEDAPIError.invalidURL
        }

        do {
            async let capabilities = fetchPinCapabilities(for: device)
            let (data, response) = try await urlSession.data(from: url)
            try validateHTTPResponse(response)
            let resolvedCapabilities = (try? await capabilities) ?? .empty
            return try JSONDecoder().decode(WLEDPinInfoResponse.self, from: data).model(capabilities: resolvedCapabilities)
        } catch let apiError as WLEDAPIError {
            throw apiError
        } catch let decodingError as DecodingError {
            throw WLEDAPIError.decodingError(decodingError)
        } catch {
            throw WLEDAPIError.networkError(error)
        }
    }

    func fetchMatrixInfo(for device: WLEDDevice) async throws -> WLEDMatrixInfo {
        async let rawConfig = fetchRawConfig(for: device)
        async let infoRoot = fetchRawInfo(for: device)
        async let settingsScript = fetch2DSettingsScript(for: device)

        let root = resolvedConfigRoot(try await rawConfig)
        let info = (try? await infoRoot) ?? [:]
        let script = (try? await settingsScript) ?? ""

        let hw = root["hw"] as? [String: Any] ?? [:]
        let led = hw["led"] as? [String: Any] ?? [:]
        let matrix = led["matrix"] as? [String: Any]
        let panels = matrixPanels(from: matrix)
        let scriptMode = parse2DMode(from: script)
        let infoMatrix = (info["leds"] as? [String: Any])?["matrix"] as? [String: Any]

        let mode: WLEDMatrixMode = {
            if scriptMode == 1 { return .matrix }
            if matrix != nil || infoMatrix != nil { return .matrix }
            return .strip
        }()

        let derivedDimensions = matrixDimensions(from: panels)
        return WLEDMatrixInfo(
            mode: mode,
            maxPanels: parseJavaScriptIntAssignment(named: "maxPanels", in: script),
            totalLEDs: intValue(led["total"]) ?? intValue((info["leds"] as? [String: Any])?["count"]),
            matrixWidth: intValue(infoMatrix?["w"]) ?? derivedDimensions.width,
            matrixHeight: intValue(infoMatrix?["h"]) ?? derivedDimensions.height,
            configuredPanelCount: intValue(matrix?["mpc"]) ?? panels.count,
            panels: panels
        )
    }

    func fetchSecurityAboutInfo(for device: WLEDDevice) async throws -> WLEDSecurityAboutInfo {
        let info = try await fetchRawInfo(for: device)
        return WLEDSecurityAboutInfo(
            version: stringValue(info["ver"]),
            buildID: stringValue(info["vid"]),
            brand: stringValue(info["brand"]),
            product: stringValue(info["product"]),
            architecture: stringValue(info["arch"]),
            core: stringValue(info["core"]),
            freeHeap: intValue(info["freeheap"]),
            uptime: intValue(info["uptime"])
        )
    }

    func factoryReset(_ device: WLEDDevice) async throws {
        guard let url = URL(string: "http://\(device.ipAddress)/settings/sec") else {
            throw WLEDAPIError.invalidURL
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = formURLEncodedData([("RS", "on")])
            let (_, response) = try await urlSession.data(for: request)
            try validateHTTPResponse(response)
        } catch let apiError as WLEDAPIError {
            throw apiError
        } catch {
            throw WLEDAPIError.networkError(error)
        }
    }

    func fetchUsermodsInfo(for device: WLEDDevice) async throws -> WLEDUsermodsInfo {
        let root = resolvedConfigRoot(try await fetchRawConfig(for: device))
        guard let usermods = root["um"] as? [String: Any] else {
            return WLEDUsermodsInfo(modules: [])
        }

        let modules = usermods.keys.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }.map { name in
            let value = usermods[name]
            return WLEDUsermodModule(
                name: name,
                rows: flattenedUsermodRows(value, prefix: name)
            )
        }

        return WLEDUsermodsInfo(modules: modules)
    }

    func fetchUsermodsDraft(for device: WLEDDevice) async throws -> WLEDUsermodsDraft {
        let root = resolvedConfigRoot(try await fetchRawConfig(for: device))
        return usermodsDraft(from: root)
    }

    func saveUsermods(
        settingsDraft: WLEDSettingsDraft,
        usermodsDraft: WLEDUsermodsDraft,
        for device: WLEDDevice
    ) async throws -> WLEDSettingsSaveResult {
        let settingsErrors = settingsDraft.validationErrors()
        guard settingsErrors.isEmpty else {
            throw WLEDAPIError.invalidConfiguration
        }
        try validateUsermodsDraft(usermodsDraft)

        let changedSettings = settingsDraft.changedFields
        let changedUsermodFields = usermodsDraft.changedFields
        guard !changedSettings.isEmpty || !changedUsermodFields.isEmpty else {
            return WLEDSettingsSaveResult(savedKeys: [], sideEffects: [], requiresRefresh: false)
        }

        let root = resolvedConfigRoot(try await fetchRawConfig(for: device))
        try await postUsermodsSettingsForm(root, draft: settingsDraft, usermodsDraft: usermodsDraft, for: device)

        let verifiedDraft = try await fetchUsermodsDraft(for: device)
        let verifiedFields = Dictionary(
            uniqueKeysWithValues: verifiedDraft.modules.flatMap(\.fields).map { ($0.id, $0) }
        )
        for field in changedUsermodFields {
            guard let verifiedField = verifiedFields[field.id], usermodFieldsMatch(field, verifiedField) else {
                throw WLEDAdvancedSettingsError.usermodVerificationFailed(
                    "WLED did not confirm the saved value for \(field.label)."
                )
            }
        }

        var effects = settingsDraft.sideEffects
        for effect in usermodSideEffects(for: changedSettings, dynamicFields: changedUsermodFields) where !effects.contains(effect) {
            effects.append(effect)
        }
        let savedKeys = Set(changedSettings.map(\.key) + changedUsermodFields.map(\.id))
        return WLEDSettingsSaveResult(
            savedKeys: savedKeys,
            sideEffects: effects,
            requiresRefresh: effects.contains(.reboot)
        )
    }

    private func fetchPinCapabilities(for device: WLEDDevice) async throws -> WLEDPinCapabilities {
        guard let url = URL(string: "http://\(device.ipAddress)/settings/s.js?p=11") else {
            throw WLEDAPIError.invalidURL
        }

        let (data, response) = try await urlSession.data(from: url)
        try validateHTTPResponse(response)
        guard let script = String(data: data, encoding: .utf8) else {
            return .empty
        }
        return WLEDPinCapabilities(
            touch: parseJavaScriptIntArray(named: "touch", in: script),
            inputOnly: parseJavaScriptIntArray(named: "ro_gpio", in: script),
            analog: parseJavaScriptIntArray(named: "adc", in: script)
        )
    }

    private func fetchRawInfo(for device: WLEDDevice) async throws -> [String: Any] {
        guard let url = URL(string: "http://\(device.ipAddress)/json/info") else {
            throw WLEDAPIError.invalidURL
        }

        let (data, response) = try await urlSession.data(from: url)
        try validateHTTPResponse(response)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WLEDAPIError.invalidResponse
        }
        return json
    }

    private func fetch2DSettingsScript(for device: WLEDDevice) async throws -> String {
        guard let url = URL(string: "http://\(device.ipAddress)/settings/s.js?p=10") else {
            throw WLEDAPIError.invalidURL
        }

        let (data, response) = try await urlSession.data(from: url)
        try validateHTTPResponse(response)
        return String(data: data, encoding: .utf8) ?? ""
    }

    func saveLEDOutputDraft(_ draft: WLEDLEDOutputDraft, for device: WLEDDevice) async throws -> WLEDSettingsSaveResult {
        let errors = draft.validationErrors()
        guard errors.isEmpty else {
            throw WLEDAPIError.invalidConfiguration
        }

        guard draft.isDirty else {
            return WLEDSettingsSaveResult(savedKeys: [], sideEffects: [], requiresRefresh: false)
        }

        var rawConfig = try await fetchRawConfig(for: device)
        var root = resolvedConfigRoot(rawConfig)
        var hw = root["hw"] as? [String: Any] ?? [:]
        var led = hw["led"] as? [String: Any] ?? [:]
        let existing = led["ins"] as? [[String: Any]] ?? []

        let updatedOutputs = draft.outputs.enumerated().map { index, output -> [String: Any] in
            var bus = existing.indices.contains(index) ? existing[index] : [:]
            bus["type"] = output.type
            bus["pin"] = output.parsedPins ?? []
            bus["len"] = max(0, output.length)
            bus["start"] = max(0, output.start)
            bus["skip"] = max(0, output.skip)
            bus["rev"] = output.reverse
            bus["ref"] = output.refreshWhenOff
            bus["order"] = packedColorOrder(colorOrder: output.colorOrder, whiteChannelSwap: output.whiteChannelSwap)
            bus["rgbwm"] = output.autoWhiteMode
            bus["freq"] = output.frequency
            bus["ledma"] = max(0, output.currentMilliamps)
            bus["maxpwr"] = output.perOutputLimiter ? max(0, output.maxPowerMilliamps) : 0
            bus["drv"] = output.driverType
            bus.removeValue(forKey: "per")
            return bus
        }

        led["ins"] = updatedOutputs
        led["total"] = updatedOutputs.reduce(0) { total, bus in
            total + (bus["len"] as? Int ?? 0)
        }
        hw["led"] = led
        let normalizedColorOverrides = draft.normalizedColorOverrides
        hw["com"] = normalizedColorOverrides.map { mapping in
            [
                "start": max(0, mapping.start),
                "len": max(1, mapping.length),
                "order": packedColorOrder(
                    colorOrder: mapping.colorOrder,
                    whiteChannelSwap: mapping.whiteChannelSwap
                )
            ]
        }
        root["hw"] = hw

        if rawConfig["cfg"] is [String: Any] {
            rawConfig["cfg"] = root
        } else {
            rawConfig = root
        }

        if needsLEDSettingsFormSave(for: draft) {
            try await postLEDSettingsForm(root, for: device)
        } else {
            try await postRawConfig(rawConfig, for: device)
        }
        try await verifyLEDOutputDraft(draft, for: device)

        return WLEDSettingsSaveResult(
            savedKeys: ["LEDOUT"],
            sideEffects: draft.sideEffects,
            requiresRefresh: true
        )
    }

    // MARK: - Config Transport

    private func fetchRawConfig(for device: WLEDDevice) async throws -> [String: Any] {
        guard let url = URL(string: "http://\(device.ipAddress)/json/cfg") else {
            throw WLEDAPIError.invalidURL
        }

        do {
            let (data, response) = try await urlSession.data(from: url)
            try validateHTTPResponse(response)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw WLEDAPIError.invalidResponse
            }
            return json
        } catch let apiError as WLEDAPIError {
            throw apiError
        } catch let decodingError as DecodingError {
            throw WLEDAPIError.decodingError(decodingError)
        } catch {
            throw WLEDAPIError.networkError(error)
        }
    }

    private func postRawConfig(_ config: [String: Any], for device: WLEDDevice) async throws {
        guard let url = URL(string: "http://\(device.ipAddress)/json/cfg") else {
            throw WLEDAPIError.invalidURL
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: config)
            let (_, response) = try await urlSession.data(for: request)
            try validateHTTPResponse(response)
        } catch let apiError as WLEDAPIError {
            throw apiError
        } catch {
            throw WLEDAPIError.networkError(error)
        }
    }

    private func postLEDSettingsForm(_ config: [String: Any], for device: WLEDDevice) async throws {
        guard let url = URL(string: "http://\(device.ipAddress)/settings/leds") else {
            throw WLEDAPIError.invalidURL
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = ledSettingsFormBody(from: config)
            let (_, response) = try await urlSession.data(for: request)
            try validateHTTPResponse(response)
        } catch let apiError as WLEDAPIError {
            throw apiError
        } catch {
            throw WLEDAPIError.networkError(error)
        }
    }

    private func postWiFiSettingsForm(
        _ config: [String: Any],
        for device: WLEDDevice,
        secretOverrides: [String: String] = [:]
    ) async throws {
        guard let url = URL(string: "http://\(device.ipAddress)/settings/wifi") else {
            throw WLEDAPIError.invalidURL
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = wifiSettingsFormBody(from: config, secretOverrides: secretOverrides)
            let (_, response) = try await urlSession.data(for: request)
            try validateHTTPResponse(response)
        } catch let apiError as WLEDAPIError {
            throw apiError
        } catch {
            throw WLEDAPIError.networkError(error)
        }
    }

    private func postSyncSettingsForm(
        _ config: [String: Any],
        for device: WLEDDevice,
        secretOverrides: [String: String] = [:]
    ) async throws {
        guard let url = URL(string: "http://\(device.ipAddress)/settings/sync") else {
            throw WLEDAPIError.invalidURL
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = syncSettingsFormBody(from: config, secretOverrides: secretOverrides)
            let (_, response) = try await urlSession.data(for: request)
            try validateHTTPResponse(response)
        } catch let apiError as WLEDAPIError {
            throw apiError
        } catch {
            throw WLEDAPIError.networkError(error)
        }
    }

    private func postTimeSettingsForm(_ config: [String: Any], for device: WLEDDevice) async throws {
        guard let url = URL(string: "http://\(device.ipAddress)/settings/time") else {
            throw WLEDAPIError.invalidURL
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = timeSettingsFormBody(from: config)
            let (_, response) = try await urlSession.data(for: request)
            try validateHTTPResponse(response)
        } catch let apiError as WLEDAPIError {
            throw apiError
        } catch {
            throw WLEDAPIError.networkError(error)
        }
    }

    private func postSecuritySettingsForm(
        _ config: [String: Any],
        for device: WLEDDevice,
        secretOverrides: [String: String] = [:]
    ) async throws {
        guard let url = URL(string: "http://\(device.ipAddress)/settings/sec") else {
            throw WLEDAPIError.invalidURL
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = securitySettingsFormBody(from: config, secretOverrides: secretOverrides)
            let (_, response) = try await urlSession.data(for: request)
            try validateHTTPResponse(response)
        } catch let apiError as WLEDAPIError {
            throw apiError
        } catch {
            throw WLEDAPIError.networkError(error)
        }
    }

    private func postUsermodsSettingsForm(
        _ config: [String: Any],
        draft: WLEDSettingsDraft,
        usermodsDraft: WLEDUsermodsDraft? = nil,
        for device: WLEDDevice
    ) async throws {
        guard let url = URL(string: "http://\(device.ipAddress)/settings/um") else {
            throw WLEDAPIError.invalidURL
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = usermodsSettingsFormBody(
                from: config,
                draft: draft,
                usermodsDraft: usermodsDraft ?? self.usermodsDraft(from: config)
            )
            let (_, response) = try await urlSession.data(for: request)
            try validateHTTPResponse(response)
        } catch let apiError as WLEDAPIError {
            throw apiError
        } catch {
            throw WLEDAPIError.networkError(error)
        }
    }

    private func postDMXOutputSettingsForm(_ config: [String: Any], for device: WLEDDevice) async throws {
        guard let url = URL(string: "http://\(device.ipAddress)/settings/dmx") else {
            throw WLEDAPIError.invalidURL
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = dmxOutputSettingsFormBody(from: config)
            let (_, response) = try await urlSession.data(for: request)
            try validateHTTPResponse(response)
        } catch let apiError as WLEDAPIError {
            throw apiError
        } catch {
            throw WLEDAPIError.networkError(error)
        }
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw WLEDAPIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw WLEDAPIError.httpError(http.statusCode)
        }
    }

    private func parseJavaScriptIntArray(named name: String, in script: String) -> Set<Int> {
        let pattern = #"d\.\#(name)\s*=\s*\[([^\]]*)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(script.startIndex..<script.endIndex, in: script)
        guard let match = regex.firstMatch(in: script, range: range),
              match.numberOfRanges > 1,
              let valuesRange = Range(match.range(at: 1), in: script) else {
            return []
        }
        return Set(
            script[valuesRange]
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        )
    }

    private func parseJavaScriptIntAssignment(named name: String, in script: String) -> Int? {
        let pattern = #"\#(name)\s*=\s*(-?\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(script.startIndex..<script.endIndex, in: script)
        guard let match = regex.firstMatch(in: script, range: range),
              let valueRange = Range(match.range(at: 1), in: script) else {
            return nil
        }
        return Int(script[valueRange])
    }

    private func parse2DMode(from script: String) -> Int? {
        let pattern = #"Sf\.SOMP\.value\s*=\s*(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(script.startIndex..<script.endIndex, in: script)
        guard let match = regex.firstMatch(in: script, range: range),
              let valueRange = Range(match.range(at: 1), in: script) else {
            return nil
        }
        return Int(script[valueRange])
    }

    private func matrixPanels(from matrix: [String: Any]?) -> [WLEDMatrixPanel] {
        guard let panels = matrix?["panels"] as? [[String: Any]] else {
            return []
        }

        return panels.enumerated().map { index, panel in
            WLEDMatrixPanel(
                index: index,
                bottomStart: boolValue(panel["b"]) ?? false,
                rightStart: boolValue(panel["r"]) ?? false,
                vertical: boolValue(panel["v"]) ?? false,
                serpentine: boolValue(panel["s"]) ?? false,
                xOffset: intValue(panel["x"]) ?? 0,
                yOffset: intValue(panel["y"]) ?? 0,
                width: intValue(panel["w"]) ?? 0,
                height: intValue(panel["h"]) ?? 0
            )
        }
    }

    private func matrixDimensions(from panels: [WLEDMatrixPanel]) -> (width: Int?, height: Int?) {
        guard !panels.isEmpty else {
            return (nil, nil)
        }
        let width = panels.map { $0.xOffset + $0.width }.max()
        let height = panels.map { $0.yOffset + $0.height }.max()
        return (width, height)
    }

    private func verifySavedFields(
        _ fields: [WLEDSettingDescriptor],
        from draft: WLEDSettingsDraft,
        for device: WLEDDevice
    ) async throws {
        let latest = resolvedConfigRoot(try await fetchRawConfig(for: device))
        for field in fields {
            guard let path = field.configPath, let expected = draft.values[field.key] else { continue }
            let observed = coerceValue(WLEDSettingValue.fromJSON(resolve(path: path, in: latest)), for: field, config: latest)
            let expectedEncoded = coerceValue(encodeValue(expected, field: field, draft: draft), for: field, config: latest)
            guard observed == expectedEncoded else {
                throw WLEDAPIError.invalidConfiguration
            }
        }
    }

    private func verifyLEDOutputDraft(_ draft: WLEDLEDOutputDraft, for device: WLEDDevice) async throws {
        var latest: WLEDLEDOutputDraft?

        for attempt in 0..<5 {
            let verified = try await fetchLEDOutputDraft(for: device)
            latest = verified
            if ledOutputsMatchWLED(verified.outputs, draft.outputs),
               verified.colorOverrides == draft.normalizedColorOverrides {
                return
            }

            if attempt < 4 {
                try await Task.sleep(nanoseconds: 250_000_000)
            }
        }

        throw WLEDAdvancedSettingsError.ledOutputVerificationFailed(
            ledOutputVerificationMessage(expected: draft, observed: latest)
        )
    }

    private func ledOutputsMatchWLED(_ observed: [WLEDLEDOutput], _ expected: [WLEDLEDOutput]) -> Bool {
        guard observed.count == expected.count else { return false }
        return zip(observed, expected).allSatisfy { observed, expected in
            observed.type == expected.type
                && normalizedPinString(observed.pins) == normalizedPinString(expected.pins)
                && observed.length == expected.length
                && observed.start == expected.start
                && observed.skip == expected.skip
                && observed.reverse == expected.reverse
                && observed.refreshWhenOff == expected.refreshWhenOff
                && observed.colorOrder == expected.colorOrder
                && observed.whiteChannelSwap == expected.whiteChannelSwap
                && observed.autoWhiteMode == expected.autoWhiteMode
                && observed.frequency == expected.frequency
                && observed.currentMilliamps == expected.currentMilliamps
                && observed.maxPowerMilliamps == (expected.perOutputLimiter ? expected.maxPowerMilliamps : 0)
                && observed.driverType == expected.driverType
                && observed.perOutputLimiter == expected.perOutputLimiter
        }
    }

    private func ledOutputVerificationMessage(expected: WLEDLEDOutputDraft, observed: WLEDLEDOutputDraft?) -> String {
        if expected.normalizedColorOverrides.isEmpty, observed?.colorOverrides.isEmpty == false {
            return "WLED accepted the save, but this firmware did not clear color order overrides through /json/cfg yet. Restart WLED, then refresh this category. If the override remains, remove it once from the WLED page."
        }

        return "WLED accepted the save, but its LED configuration has not reflected the change yet. Restart WLED, then refresh this category."
    }

    private func needsLEDSettingsFormSave(for draft: WLEDLEDOutputDraft) -> Bool {
        !draft.originalColorOverrides.isEmpty && draft.normalizedColorOverrides.isEmpty
    }

    private func needsLEDSettingsFormSave(for fields: [WLEDSettingDescriptor]) -> Bool {
        fields.contains { field in
            field.key == "ABL" || field.key == "MA"
        }
    }

    private func needsWiFiSettingsFormSave(
        for category: WLEDSettingsCategoryDescriptor,
        fields: [WLEDSettingDescriptor]
    ) -> Bool {
        category.id == "wifi-network" && !fields.isEmpty
    }

    private func needsSyncSettingsFormSave(
        for category: WLEDSettingsCategoryDescriptor,
        fields: [WLEDSettingDescriptor]
    ) -> Bool {
        category.id == "sync-interfaces" && !fields.isEmpty
    }

    private func needsTimeSettingsFormSave(
        for category: WLEDSettingsCategoryDescriptor,
        fields: [WLEDSettingDescriptor]
    ) -> Bool {
        category.id == "time-macros" && !fields.isEmpty
    }

    private func needsSecuritySettingsFormSave(
        for category: WLEDSettingsCategoryDescriptor,
        fields: [WLEDSettingDescriptor]
    ) -> Bool {
        category.id == "security-updates" && !fields.isEmpty
    }

    private func needsUsermodsSettingsFormSave(
        for category: WLEDSettingsCategoryDescriptor,
        fields: [WLEDSettingDescriptor]
    ) -> Bool {
        category.id == "usermods" && !fields.isEmpty
    }

    private func needsDMXOutputSettingsFormSave(
        for category: WLEDSettingsCategoryDescriptor,
        fields: [WLEDSettingDescriptor]
    ) -> Bool {
        category.id == "dmx-output" && !fields.isEmpty
    }

    private func actionOnlyFields(
        in draft: WLEDSettingsDraft,
        fields: [WLEDSettingDescriptor]
    ) -> [WLEDSettingDescriptor] {
        guard draft.category.id == "usermods" else { return [] }
        return fields.filter { $0.key == "RBT" }
    }

    private func verifiedWiFiSecretFields(
        in draft: WLEDSettingsDraft,
        fields: [WLEDSettingDescriptor]
    ) -> [WLEDSettingDescriptor] {
        guard draft.category.id == "wifi-network" else { return [] }
        let verifiedKeys: Set<String> = ["AP"]
        return fields.filter { field in
            guard field.secret, verifiedKeys.contains(field.key) else { return false }
            guard let state = draft.secretStates[field.key] else { return false }
            if case .preserve = state { return false }
            return true
        }
    }

    private func wifiSecretOverrides(
        from draft: WLEDSettingsDraft,
        fields: [WLEDSettingDescriptor]
    ) -> [String: String] {
        fields.reduce(into: [String: String]()) { result, field in
            switch draft.secretStates[field.key] {
            case .replace(let value):
                result[field.key] = value
            case .clear:
                result[field.key] = ""
            case .preserve, .none:
                break
            }
        }
    }

    private func verifiedSyncSecretFields(
        in draft: WLEDSettingsDraft,
        fields: [WLEDSettingDescriptor]
    ) -> [WLEDSettingDescriptor] {
        guard draft.category.id == "sync-interfaces" else { return [] }
        let verifiedKeys: Set<String> = ["MQPASS"]
        return fields.filter { field in
            guard field.secret, verifiedKeys.contains(field.key) else { return false }
            guard let state = draft.secretStates[field.key] else { return false }
            if case .preserve = state { return false }
            return true
        }
    }

    private func syncSecretOverrides(
        from draft: WLEDSettingsDraft,
        fields: [WLEDSettingDescriptor]
    ) -> [String: String] {
        fields.reduce(into: [String: String]()) { result, field in
            switch draft.secretStates[field.key] {
            case .replace(let value):
                result[field.key] = value
            case .clear:
                result[field.key] = ""
            case .preserve, .none:
                break
            }
        }
    }

    private func verifiedSecuritySecretFields(
        in draft: WLEDSettingsDraft,
        fields: [WLEDSettingDescriptor]
    ) -> [WLEDSettingDescriptor] {
        guard draft.category.id == "security-updates" else { return [] }
        let verifiedKeys: Set<String> = ["PIN", "OP"]
        return fields.filter { field in
            guard field.secret, verifiedKeys.contains(field.key) else { return false }
            guard let state = draft.secretStates[field.key] else { return false }
            if case .preserve = state { return false }
            return true
        }
    }

    private func securitySecretOverrides(
        from draft: WLEDSettingsDraft,
        fields: [WLEDSettingDescriptor]
    ) -> [String: String] {
        fields.reduce(into: [String: String]()) { result, field in
            switch draft.secretStates[field.key] {
            case .replace(let value):
                result[field.key] = value
            case .clear:
                result[field.key] = ""
            case .preserve, .none:
                break
            }
        }
    }

    private func wifiSettingsFormBody(
        from root: [String: Any],
        secretOverrides: [String: String] = [:]
    ) -> Data {
        let nw = root["nw"] as? [String: Any] ?? [:]
        let id = root["id"] as? [String: Any] ?? [:]
        let ap = root["ap"] as? [String: Any] ?? [:]
        let wifi = root["wifi"] as? [String: Any] ?? [:]
        let eth = root["eth"] as? [String: Any] ?? [:]

        var form: [(String, String)] = []
        func add(_ name: String, _ value: Any?) {
            form.append((name, formString(value)))
        }
        func addCheckbox(_ name: String, _ enabled: Bool) {
            if enabled { add(name, "on") }
        }

        let networks = nw["ins"] as? [[String: Any]] ?? []
        for (index, network) in networks.enumerated() {
            let suffix = String(index)
            add("CS\(suffix)", network["ssid"] as? String ?? "")
            add("PW\(suffix)", secretOverrides["PW\(suffix)"] ?? secretPlaceholder(configuredLength: intValue(network["pskl"]) ?? 0))
            add("BS\(suffix)", network["bssid"] as? String ?? "")
            addIPAddressFields(prefix: "IP\(suffix)", value: network["ip"], into: &form)
            addIPAddressFields(prefix: "GW\(suffix)", value: network["gw"], into: &form)
            addIPAddressFields(prefix: "SN\(suffix)", value: network["sn"], fallback: [255, 255, 255, 0], into: &form)
            add("ET\(suffix)", intValue(network["enc_type"]) ?? 0)
            add("EA\(suffix)", network["e_anon_ident"] as? String ?? "")
            add("EI\(suffix)", network["e_ident"] as? String ?? "")
        }

        let dns = ipComponents(from: nw["dns"])
        for index in 0..<4 {
            add("D\(index)", dns[index])
        }

        add("ETH", intValue(eth["type"]) ?? 0)
        add("CM", normalizeMDNSName(id["mdns"] as? String ?? ""))
        add("AS", ap["ssid"] as? String ?? "")
        addCheckbox("AH", boolValue(ap["hide"]) ?? false)
        add("AP", secretOverrides["AP"] ?? secretPlaceholder(configuredLength: intValue(ap["pskl"]) ?? 0))
        add("AC", intValue(ap["chan"]) ?? 1)
        add("AB", intValue(ap["behav"]) ?? 0)
        addCheckbox("FG", boolValue(wifi["phy"]) ?? false)
        addCheckbox("WS", !(boolValue(wifi["sleep"]) ?? true))
        add("TX", intValue(wifi["txpwr"]) ?? 78)
        addCheckbox("RE", boolValue(nw["espnow"]) ?? false)

        let remotes = nw["linked_remote"] as? [Any] ?? []
        for (index, remote) in remotes.prefix(10).enumerated() {
            add("RM\(index)", remote as? String ?? formString(remote))
        }

        return formURLEncodedData(form)
    }

    private func ledSettingsFormBody(from root: [String: Any]) -> Data {
        let hw = root["hw"] as? [String: Any] ?? [:]
        let led = hw["led"] as? [String: Any] ?? [:]
        let light = root["light"] as? [String: Any] ?? [:]
        let defaultState = root["def"] as? [String: Any] ?? [:]
        let gc = light["gc"] as? [String: Any] ?? [:]
        let transition = light["tr"] as? [String: Any] ?? [:]
        let nightlight = light["nl"] as? [String: Any] ?? [:]
        let button = hw["btn"] as? [String: Any] ?? [:]
        let ir = hw["ir"] as? [String: Any] ?? [:]
        let relay = hw["relay"] as? [String: Any] ?? [:]

        var form: [(String, String)] = []
        func add(_ name: String, _ value: Any?) {
            form.append((name, formString(value)))
        }
        func addCheckbox(_ name: String, _ enabled: Bool) {
            if enabled { add(name, "on") }
        }

        add("BF", intValue(light["scale-bri"]) ?? 100)
        addCheckbox("ABL", (intValue(led["maxpwr"]) ?? 0) > 0)
        add("MA", intValue(led["maxpwr"]) ?? 0)
        addCheckbox("PPL", (led["ins"] as? [[String: Any]] ?? []).contains { (intValue($0["maxpwr"]) ?? 0) > 0 })
        addCheckbox("MS", boolValue(light["aseg"]) ?? false)
        addCheckbox("CCT", boolValue(led["cct"]) ?? false)
        addCheckbox("CR", boolValue(led["cr"]) ?? false)
        addCheckbox("IC", boolValue(led["ic"]) ?? false)
        add("CB", intValue(led["cb"]) ?? 0)
        add("AW", intValue(led["rgbwm"]) ?? 0)
        add("FR", intValue(led["fps"]) ?? 42)

        let outputs = led["ins"] as? [[String: Any]] ?? []
        for (index, bus) in outputs.enumerated() {
            let suffix = formIndexSuffix(index)
            let pins = pinArray(from: bus["pin"])
            add("L0\(suffix)", pins.indices.contains(0) ? pins[0] : "")
            for pinIndex in 1..<5 where pins.indices.contains(pinIndex) {
                add("L\(pinIndex)\(suffix)", pins[pinIndex])
            }
            let type = intValue(bus["type"]) ?? 22
            let packedOrder = intValue(bus["order"]) ?? intValue(bus["co"]) ?? 0
            let unpackedOrder = unpackedColorOrder(from: packedOrder)
            add("LT\(suffix)", type)
            add("LC\(suffix)", max(1, intValue(bus["len"]) ?? 1))
            add("LS\(suffix)", max(0, intValue(bus["start"]) ?? 0))
            add("CO\(suffix)", unpackedOrder.colorOrder)
            add("WO\(suffix)", unpackedOrder.whiteChannelSwap)
            add("SL\(suffix)", max(0, intValue(bus["skip"]) ?? 0))
            add("AW\(suffix)", intValue(bus["rgbwm"]) ?? 0)
            add("SP\(suffix)", ledSettingsFrequencyOption(type: type, frequency: intValue(bus["freq"]) ?? 0))
            add("LA\(suffix)", max(0, intValue(bus["ledma"]) ?? 55))
            add("MA\(suffix)", max(0, intValue(bus["maxpwr"]) ?? 0))
            add("LD\(suffix)", intValue(bus["drv"]) ?? 0)
            add("HS\(suffix)", bus["text"] as? String ?? "")
            addCheckbox("CV\(suffix)", boolValue(bus["rev"]) ?? false)
            addCheckbox("RF\(suffix)", boolValue(bus["ref"]) ?? false)
        }

        let colorOverrides = hw["com"] as? [[String: Any]] ?? []
        for (index, mapping) in colorOverrides.enumerated() {
            let suffix = formIndexSuffix(index)
            let packedOrder = intValue(mapping["order"]) ?? 0
            let unpackedOrder = unpackedColorOrder(from: packedOrder)
            add("XS\(suffix)", max(0, intValue(mapping["start"]) ?? 0))
            add("XC\(suffix)", max(1, intValue(mapping["len"]) ?? 1))
            add("XO\(suffix)", unpackedOrder.colorOrder)
            add("XW\(suffix)", unpackedOrder.whiteChannelSwap)
        }

        addCheckbox("IP", !(boolValue(button["pull"]) ?? true))
        add("TT", intValue(button["tt"]) ?? 32)
        let buttons = button["ins"] as? [[String: Any]] ?? []
        for (index, entry) in buttons.enumerated() {
            let suffix = formIndexSuffix(index)
            add("BT\(suffix)", pinArray(from: entry["pin"]).first ?? -1)
            add("BE\(suffix)", intValue(entry["type"]) ?? 0)
        }

        add("IR", intValue(ir["pin"]) ?? -1)
        add("IT", intValue(ir["type"]) ?? 0)
        addCheckbox("MSO", !(boolValue(ir["sel"]) ?? true))
        add("RL", intValue(relay["pin"]) ?? -1)
        addCheckbox("RM", !(boolValue(relay["rev"]) ?? true))
        addCheckbox("RO", boolValue(relay["odrain"]) ?? false)

        addCheckbox("BO", boolValue(defaultState["on"]) ?? true)
        add("CA", intValue(defaultState["bri"]) ?? 128)
        add("BP", intValue(defaultState["ps"]) ?? 0)
        addCheckbox("GC", doubleValue(gc["col"]) != 1)
        addCheckbox("GB", doubleValue(gc["bri"]) != 1)
        add("GV", doubleValue(gc["val"]) ?? doubleValue(gc["col"]) ?? 2.2)
        add("TD", (intValue(transition["dur"]) ?? 7) * 100)
        add("TP", intValue(transition["rpc"]) ?? 5)
        addCheckbox("TH", boolValue(transition["hrp"]) ?? true)
        add("TL", intValue(nightlight["dur"]) ?? 60)
        add("TB", intValue(nightlight["tbri"]) ?? 0)
        add("TW", intValue(nightlight["mode"]) ?? 0)
        add("PB", intValue(light["pal-mode"]) ?? 0)

        return formURLEncodedData(form)
    }

    private func syncSettingsFormBody(
        from root: [String: Any],
        secretOverrides: [String: String] = [:]
    ) -> Data {
        let interfaces = root["if"] as? [String: Any] ?? [:]
        let sync = interfaces["sync"] as? [String: Any] ?? [:]
        let recv = sync["recv"] as? [String: Any] ?? [:]
        let send = sync["send"] as? [String: Any] ?? [:]
        let nodes = interfaces["nodes"] as? [String: Any] ?? [:]
        let live = interfaces["live"] as? [String: Any] ?? [:]
        let dmx = live["dmx"] as? [String: Any] ?? [:]
        let va = interfaces["va"] as? [String: Any] ?? [:]
        let mqtt = interfaces["mqtt"] as? [String: Any] ?? [:]
        let hue = interfaces["hue"] as? [String: Any] ?? [:]
        let id = root["id"] as? [String: Any] ?? [:]
        let hw = root["hw"] as? [String: Any] ?? [:]
        let button = hw["btn"] as? [String: Any] ?? [:]

        var form: [(String, String)] = []
        func add(_ name: String, _ value: Any?) {
            form.append((name, formString(value)))
        }
        func addCheckbox(_ name: String, _ enabled: Bool) {
            if enabled { add(name, "on") }
        }

        add("UP", intValue(sync["port0"]) ?? 21324)
        add("U2", intValue(sync["port1"]) ?? 65506)
        addCheckbox("EN", boolValue(sync["espnow"]) ?? false)
        add("GS", intValue(send["grp"]) ?? 1)
        add("GR", intValue(recv["grp"]) ?? 1)

        addCheckbox("RB", boolValue(recv["bri"]) ?? true)
        addCheckbox("RC", boolValue(recv["col"]) ?? true)
        addCheckbox("RX", boolValue(recv["fx"]) ?? true)
        addCheckbox("RP", boolValue(recv["pal"]) ?? true)
        addCheckbox("SO", boolValue(recv["seg"]) ?? false)
        addCheckbox("SG", boolValue(recv["sb"]) ?? false)
        addCheckbox("SS", boolValue(send["en"]) ?? false)
        addCheckbox("SD", boolValue(send["dir"]) ?? false)
        addCheckbox("SB", boolValue(send["btn"]) ?? false)
        addCheckbox("SA", boolValue(send["va"]) ?? false)
        addCheckbox("SH", boolValue(send["hue"]) ?? false)
        add("UR", intValue(send["ret"]) ?? 0)

        addCheckbox("NL", boolValue(nodes["list"]) ?? true)
        addCheckbox("NB", boolValue(nodes["bcast"]) ?? true)

        addCheckbox("RD", boolValue(live["en"]) ?? false)
        addCheckbox("MO", boolValue(live["mso"]) ?? false)
        addCheckbox("RLM", boolValue(live["rlm"]) ?? false)
        add("EP", intValue(live["port"]) ?? 5568)
        addCheckbox("EM", boolValue(live["mc"]) ?? false)
        add("EU", intValue(dmx["uni"]) ?? 1)
        addCheckbox("ES", boolValue(dmx["seqskip"]) ?? false)
        add("DA", intValue(dmx["addr"]) ?? 1)
        add("XX", intValue(dmx["dss"]) ?? 0)
        add("PY", intValue(dmx["e131prio"]) ?? 0)
        add("DM", intValue(dmx["mode"]) ?? 0)
        add("ET", max(100, (intValue(live["timeout"]) ?? 25) * 100))
        addCheckbox("FB", boolValue(live["maxbri"]) ?? false)
        addCheckbox("RG", boolValue(live["no-gc"]) ?? true)
        add("WO", intValue(live["offset"]) ?? 0)
        add("IDMR", intValue(dmx["inputRxPin"]) ?? -1)
        add("IDMT", intValue(dmx["inputTxPin"]) ?? -1)
        add("IDME", intValue(dmx["inputEnablePin"]) ?? -1)
        add("IDMP", intValue(dmx["dmxInputPort"]) ?? 2)

        addCheckbox("AL", boolValue(va["alexa"]) ?? false)
        add("AI", id["inv"] as? String ?? "")
        add("AP", intValue(va["p"]) ?? 0)

        addCheckbox("MQ", boolValue(mqtt["en"]) ?? false)
        add("MS", mqtt["broker"] as? String ?? "")
        add("MQPORT", intValue(mqtt["port"]) ?? 1883)
        add("MQUSER", mqtt["user"] as? String ?? "")
        add("MQPASS", secretOverrides["MQPASS"] ?? secretPlaceholder(configuredLength: intValue(mqtt["pskl"]) ?? 0))
        add("MQCID", mqtt["cid"] as? String ?? "")
        let mqttTopics = mqtt["topics"] as? [String: Any] ?? [:]
        add("MD", mqttTopics["device"] as? String ?? "")
        add("MG", mqttTopics["group"] as? String ?? "")
        addCheckbox("BM", boolValue(button["mqtt"]) ?? false)
        addCheckbox("RT", boolValue(mqtt["rtn"]) ?? false)

        let hueIP = ipComponents(from: hue["ip"])
        for index in 0..<4 {
            add("H\(index)", hueIP[index])
        }
        add("HL", intValue(hue["id"]) ?? 1)
        add("HI", max(100, (intValue(hue["iv"]) ?? 25) * 100))
        addCheckbox("HP", boolValue(hue["en"]) ?? false)
        let hueRecv = hue["recv"] as? [String: Any] ?? [:]
        addCheckbox("HO", boolValue(hueRecv["on"]) ?? true)
        addCheckbox("HB", boolValue(hueRecv["bri"]) ?? true)
        addCheckbox("HC", boolValue(hueRecv["col"]) ?? true)

        // WLED's Serial section lives on the Sync form, but persists in hw.baud.
        // Preserve it on every Sync save so unrelated protocol changes cannot reset it.
        add("BD", intValue(hw["baud"]) ?? 1152)

        return formURLEncodedData(form)
    }

    private func timeSettingsFormBody(from root: [String: Any]) -> Data {
        let interfaces = root["if"] as? [String: Any] ?? [:]
        let ntp = interfaces["ntp"] as? [String: Any] ?? [:]
        let va = interfaces["va"] as? [String: Any] ?? [:]
        let light = root["light"] as? [String: Any] ?? [:]
        let nightlight = light["nl"] as? [String: Any] ?? [:]
        let overlay = root["ol"] as? [String: Any] ?? [:]
        let timers = root["timers"] as? [String: Any] ?? [:]
        let countdown = timers["cntdwn"] as? [String: Any] ?? [:]
        let hw = root["hw"] as? [String: Any] ?? [:]
        let button = hw["btn"] as? [String: Any] ?? [:]

        var form: [(String, String)] = []
        func add(_ name: String, _ value: Any?) {
            form.append((name, formString(value)))
        }
        func addCheckbox(_ name: String, _ enabled: Bool) {
            if enabled { add(name, "on") }
        }
        func addCoordinate(_ name: String, _ value: Double?) {
            let coordinate = value ?? 0
            form.append((name, String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), coordinate)))
        }

        addCheckbox("NT", boolValue(ntp["en"]) ?? true)
        add("NS", ntp["host"] as? String ?? "0.wled.pool.ntp.org")
        addCheckbox("CF", !(boolValue(ntp["ampm"]) ?? true))
        add("TZ", intValue(ntp["tz"]) ?? 0)
        add("UO", intValue(ntp["offset"]) ?? 0)
        addCoordinate("LT", doubleValue(ntp["lt"]))
        addCoordinate("LN", doubleValue(ntp["ln"]))

        addCheckbox("OL", boolValue(overlay["clock"]) ?? false)
        add("O1", intValue(overlay["min"]) ?? 0)
        add("O2", intValue(overlay["max"]) ?? 0)
        add("OM", intValue(overlay["o12pix"]) ?? 0)
        addCheckbox("O5", boolValue(overlay["o5m"]) ?? false)
        addCheckbox("OS", boolValue(overlay["osec"]) ?? false)
        addCheckbox("OB", boolValue(overlay["osb"]) ?? false)
        addCheckbox("CE", boolValue(overlay["cntdwn"]) ?? false)

        let goal = countdown["goal"] as? [Any] ?? []
        add("CY", goal.indices.contains(0) ? intValue(goal[0]) ?? 20 : 20)
        add("CI", goal.indices.contains(1) ? intValue(goal[1]) ?? 1 : 1)
        add("CD", goal.indices.contains(2) ? intValue(goal[2]) ?? 1 : 1)
        add("CH", goal.indices.contains(3) ? intValue(goal[3]) ?? 0 : 0)
        add("CM", goal.indices.contains(4) ? intValue(goal[4]) ?? 0 : 0)
        add("CS", goal.indices.contains(5) ? intValue(goal[5]) ?? 0 : 0)

        add("MC", intValue(countdown["macro"]) ?? 0)
        add("MN", intValue(nightlight["macro"]) ?? 0)
        let vaMacros = va["macros"] as? [Any] ?? []
        add("A0", vaMacros.indices.contains(0) ? intValue(vaMacros[0]) ?? 0 : 0)
        add("A1", vaMacros.indices.contains(1) ? intValue(vaMacros[1]) ?? 0 : 0)

        let buttonRows = button["ins"] as? [[String: Any]] ?? []
        for (index, row) in buttonRows.enumerated() {
            let suffix = formIndexSuffix(index)
            let macros = row["macros"] as? [Any] ?? []
            add("MP\(suffix)", macros.indices.contains(0) ? intValue(macros[0]) ?? 0 : 0)
            add("ML\(suffix)", macros.indices.contains(1) ? intValue(macros[1]) ?? 0 : 0)
            add("MD\(suffix)", macros.indices.contains(2) ? intValue(macros[2]) ?? 0 : 0)
        }

        let timerRows = timers["ins"] as? [[String: Any]] ?? []
        for (index, timer) in timerRows.enumerated() {
            let suffix = String(index)
            add("T\(suffix)", intValue(timer["macro"]) ?? 0)
            add("H\(suffix)", intValue(timer["hour"]) ?? 0)
            add("N\(suffix)", intValue(timer["min"]) ?? 0)
            let enabled = boolValue(timer["en"]) ?? ((intValue(timer["en"]) ?? 0) != 0)
            let dow = intValue(timer["dow"]) ?? 127
            add("W\(suffix)", (max(0, dow) << 1) | (enabled ? 1 : 0))
            let start = timer["start"] as? [String: Any] ?? [:]
            let end = timer["end"] as? [String: Any] ?? [:]
            add("M\(suffix)", intValue(start["mon"]) ?? 1)
            add("D\(suffix)", intValue(start["day"]) ?? 1)
            add("P\(suffix)", intValue(end["mon"]) ?? 12)
            add("E\(suffix)", intValue(end["day"]) ?? 31)
        }

        return formURLEncodedData(form)
    }

    private func securitySettingsFormBody(
        from root: [String: Any],
        secretOverrides: [String: String] = [:]
    ) -> Data {
        let ota = root["ota"] as? [String: Any] ?? [:]

        var form: [(String, String)] = []
        func add(_ name: String, _ value: Any?) {
            form.append((name, formString(value)))
        }
        func addCheckbox(_ name: String, _ enabled: Bool) {
            if enabled { add(name, "on") }
        }

        add("PIN", secretOverrides["PIN"] ?? "0000")
        addCheckbox("NO", boolValue(ota["lock"]) ?? false)
        add("OP", secretOverrides["OP"] ?? "")
        addCheckbox("OW", boolValue(ota["lock-wifi"]) ?? false)
        addCheckbox("AO", boolValue(ota["aota"]) ?? false)
        addCheckbox("SU", boolValue(ota["same-subnet"]) ?? true)

        return formURLEncodedData(form)
    }

    private func flattenedUsermodRows(_ value: Any?, prefix: String) -> [WLEDUsermodConfigRow] {
        if let object = value as? [String: Any] {
            return object.keys.sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            }.flatMap { key in
                flattenedUsermodRows(object[key], prefix: "\(prefix).\(key)")
            }
        }

        if let array = value as? [Any] {
            return array.enumerated().flatMap { index, element in
                flattenedUsermodRows(element, prefix: "\(prefix)[\(index)]")
            }
        }

        let label = prefix.split(separator: ".").last.map(String.init) ?? prefix
        return [
            WLEDUsermodConfigRow(
                path: prefix,
                label: humanizedUsermodLabel(label),
                value: usermodDisplayValue(value)
            )
        ]
    }

    private func usermodsDraft(from root: [String: Any]) -> WLEDUsermodsDraft {
        let usermods = root["um"] as? [String: Any] ?? [:]
        let modules = usermods.keys.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }.compactMap { moduleName -> WLEDUsermodModuleDraft? in
            guard let module = usermods[moduleName] as? [String: Any] else { return nil }
            var fields: [WLEDUsermodFieldDraft] = []

            for key in module.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
                guard let value = module[key] else { continue }
                if let sectionValues = value as? [String: Any] {
                    for nestedKey in sectionValues.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
                        guard let nestedValue = sectionValues[nestedKey] else { continue }
                        fields.append(
                            usermodFieldDraft(
                                moduleName: moduleName,
                                section: key,
                                key: nestedKey,
                                value: nestedValue
                            )
                        )
                    }
                } else {
                    fields.append(
                        usermodFieldDraft(
                            moduleName: moduleName,
                            section: "General",
                            key: key,
                            value: value
                        )
                    )
                }
            }
            return WLEDUsermodModuleDraft(name: moduleName, fields: fields)
        }
        return WLEDUsermodsDraft(modules: modules)
    }

    private func usermodFieldDraft(
        moduleName: String,
        section: String,
        key: String,
        value: Any
    ) -> WLEDUsermodFieldDraft {
        let isTopLevel = section == "General"
        let baseFormName = isTopLevel
            ? "\(moduleName):\(key)"
            : "\(moduleName):\(section):\(key)"
        let identifier = baseFormName
        let label = usermodFieldLabel(moduleName: moduleName, section: section, key: key)

        if let bool = boolValue(value), isBooleanJSONValue(value) {
            return WLEDUsermodFieldDraft(
                id: identifier,
                moduleName: moduleName,
                section: usermodSectionLabel(moduleName: moduleName, section: section),
                key: key,
                label: label,
                formName: baseFormName,
                kind: .boolean,
                value: bool ? "true" : "false",
                arrayValues: [],
                unsupportedValue: nil
            )
        }

        if let array = value as? [Any] {
            let numericValues = array.compactMap { value -> String? in
                guard let number = doubleValue(value) else { return nil }
                return usermodNumberString(number)
            }
            if numericValues.count == array.count {
                return WLEDUsermodFieldDraft(
                    id: identifier,
                    moduleName: moduleName,
                    section: usermodSectionLabel(moduleName: moduleName, section: section),
                    key: key,
                    label: label,
                    formName: "\(baseFormName)[]",
                    kind: .numberArray,
                    value: "",
                    arrayValues: numericValues,
                    unsupportedValue: nil
                )
            }
        }

        if let number = doubleValue(value) {
            return WLEDUsermodFieldDraft(
                id: identifier,
                moduleName: moduleName,
                section: usermodSectionLabel(moduleName: moduleName, section: section),
                key: key,
                label: label,
                formName: baseFormName,
                kind: .number,
                value: usermodNumberString(number),
                arrayValues: [],
                unsupportedValue: nil
            )
        }

        if let text = value as? String {
            return WLEDUsermodFieldDraft(
                id: identifier,
                moduleName: moduleName,
                section: usermodSectionLabel(moduleName: moduleName, section: section),
                key: key,
                label: label,
                formName: baseFormName,
                kind: .text,
                value: text,
                arrayValues: [],
                unsupportedValue: nil
            )
        }

        return WLEDUsermodFieldDraft(
            id: identifier,
            moduleName: moduleName,
            section: usermodSectionLabel(moduleName: moduleName, section: section),
            key: key,
            label: label,
            formName: baseFormName,
            kind: .unsupported,
            value: "",
            arrayValues: [],
            unsupportedValue: usermodDisplayValue(value)
        )
    }

    private func usermodNumberString(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    private func usermodSectionLabel(moduleName: String, section: String) -> String {
        guard moduleName == "AudioReactive" else {
            return section == "General" ? "General" : humanizedUsermodLabel(section).capitalized
        }
        switch section {
        case "General": return "Audio"
        case "analogmic": return "Analog microphone"
        case "digitalmic": return "Digital microphone"
        case "config": return "Input tuning"
        case "frequency": return "Frequency response"
        case "dynamics": return "Dynamics"
        case "sync": return "Sync"
        default: return humanizedUsermodLabel(section).capitalized
        }
    }

    private func isBooleanJSONValue(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else {
            return value is Bool
        }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private func usermodFieldLabel(moduleName: String, section: String, key: String) -> String {
        guard moduleName == "AudioReactive" else {
            return humanizedUsermodLabel(key).capitalized
        }
        switch (section, key) {
        case ("General", "enabled"): return "Enabled"
        case ("General", "add-palettes"): return "Add palettes"
        case ("analogmic", "pin"): return "Pin"
        case ("digitalmic", "type"): return "Type"
        case ("digitalmic", "pin"): return "I2S pins"
        case ("config", "squelch"): return "Squelch"
        case ("config", "gain"): return "Gain"
        case ("config", "AGC"): return "Automatic gain"
        case ("frequency", "scale"): return "Scale"
        case ("dynamics", "limiter"): return "Limiter"
        case ("dynamics", "rise"): return "Rise"
        case ("dynamics", "fall"): return "Fall"
        case ("sync", "port"): return "Port"
        case ("sync", "mode"): return "Mode"
        default: return humanizedUsermodLabel(key).capitalized
        }
    }

    private func validateUsermodsDraft(_ draft: WLEDUsermodsDraft) throws {
        for field in draft.modules.flatMap(\.fields) where field.isEditable {
            switch field.kind {
            case .number:
                guard Double(field.value.trimmingCharacters(in: .whitespacesAndNewlines)) != nil else {
                    throw WLEDAPIError.invalidConfiguration
                }
            case .numberArray:
                guard field.arrayValues.allSatisfy({ Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) != nil }) else {
                    throw WLEDAPIError.invalidConfiguration
                }
            case .boolean, .text, .unsupported:
                break
            }
        }
    }

    private func usermodFieldsMatch(_ expected: WLEDUsermodFieldDraft, _ actual: WLEDUsermodFieldDraft) -> Bool {
        guard expected.kind == actual.kind else { return false }
        switch expected.kind {
        case .boolean:
            return expected.boolValue == actual.boolValue
        case .number:
            guard let lhs = Double(expected.value), let rhs = Double(actual.value) else { return false }
            return abs(lhs - rhs) < 0.0001
        case .text:
            return expected.value == actual.value
        case .numberArray:
            guard expected.arrayValues.count == actual.arrayValues.count else { return false }
            return zip(expected.arrayValues, actual.arrayValues).allSatisfy { lhs, rhs in
                guard let lhs = Double(lhs), let rhs = Double(rhs) else { return false }
                return abs(lhs - rhs) < 0.0001
            }
        case .unsupported:
            return true
        }
    }

    private func usermodSideEffects(
        for settingsFields: [WLEDSettingDescriptor],
        dynamicFields: [WLEDUsermodFieldDraft]
    ) -> [WLEDSettingsSideEffect] {
        let pinChanged = settingsFields.contains { ["SDA", "SCL", "MOSI", "MISO", "SCLK", "RBT"].contains($0.key) }
            || dynamicFields.contains { field in
                field.moduleName == "AudioReactive"
                    && (field.section == "Analog microphone" || field.section == "Digital microphone")
            }
        return pinChanged ? [.reboot] : []
    }

    private func humanizedUsermodLabel(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func usermodDisplayValue(_ value: Any?) -> String {
        if let bool = value as? Bool {
            return bool ? "On" : "Off"
        }
        if let int = intValue(value) {
            return String(int)
        }
        if let double = doubleValue(value) {
            return double.rounded() == double ? String(Int(double)) : String(double)
        }
        if let string = value as? String {
            return string.isEmpty ? "Empty" : string
        }
        if value is NSNull || value == nil {
            return "Not set"
        }
        return String(describing: value ?? "")
    }

    private func usermodsSettingsFormBody(
        from root: [String: Any],
        draft: WLEDSettingsDraft,
        usermodsDraft: WLEDUsermodsDraft
    ) -> Data {
        let hw = root["hw"] as? [String: Any] ?? [:]
        let interfaces = hw["if"] as? [String: Any] ?? [:]
        let i2cPins = interfaces["i2c-pin"] as? [Any] ?? []
        let spiPins = interfaces["spi-pin"] as? [Any] ?? []

        var form: [(String, String)] = []
        func add(_ name: String, _ value: Any?) {
            form.append((name, formString(value)))
        }
        func addPin(_ name: String, fallback: Int) {
            if let value = draft.values[name] {
                add(name, Int(value.numberValue))
            } else {
                add(name, fallback)
            }
        }

        addPin("SDA", fallback: i2cPins.indices.contains(0) ? intValue(i2cPins[0]) ?? -1 : -1)
        addPin("SCL", fallback: i2cPins.indices.contains(1) ? intValue(i2cPins[1]) ?? -1 : -1)
        addPin("MOSI", fallback: spiPins.indices.contains(0) ? intValue(spiPins[0]) ?? -1 : -1)
        addPin("MISO", fallback: spiPins.indices.contains(2) ? intValue(spiPins[2]) ?? -1 : -1)
        addPin("SCLK", fallback: spiPins.indices.contains(1) ? intValue(spiPins[1]) ?? -1 : -1)

        if draft.values["RBT"]?.boolValue == true {
            add("RBT", "on")
        }

        for field in usermodsDraft.modules.flatMap(\.fields) where field.isEditable {
            switch field.kind {
            case .boolean:
                add(field.formName, "false")
                if field.boolValue {
                    add(field.formName, "true")
                }
            case .number:
                add(field.formName, "number")
                add(field.formName, field.value)
            case .text:
                add(field.formName, "text")
                add(field.formName, field.value)
            case .numberArray:
                for value in field.arrayValues {
                    add(field.formName, value)
                }
            case .unsupported:
                break
            }
        }

        return formURLEncodedData(form)
    }

    private func dmxOutputSettingsFormBody(from root: [String: Any]) -> Data {
        let dmx = root["dmx"] as? [String: Any] ?? [:]
        let fixtureMap = dmx["fixmap"] as? [Any] ?? []

        var form: [(String, String)] = []
        func add(_ name: String, _ value: Any?) {
            form.append((name, formString(value)))
        }

        add("PU", intValue(dmx["e131proxy"]) ?? 0)
        add("CN", intValue(dmx["chan"]) ?? 3)
        add("CS", intValue(dmx["start"]) ?? 1)
        add("CG", intValue(dmx["gap"]) ?? 10)
        add("SL", intValue(dmx["start-led"]) ?? 0)

        for index in 0..<15 {
            add("CH\(index + 1)", fixtureMap.indices.contains(index) ? intValue(fixtureMap[index]) ?? 0 : 0)
        }

        return formURLEncodedData(form)
    }

    // MARK: - Value Mapping

    private func resolvedConfigRoot(_ raw: [String: Any]) -> [String: Any] {
        (raw["cfg"] as? [String: Any]) ?? raw
    }

    private func coerceValue(_ value: WLEDSettingValue, for field: WLEDSettingDescriptor, config: [String: Any]) -> WLEDSettingValue {
        switch field.control {
        case .toggle:
            if field.key == "GC" || field.key == "GB" {
                return .bool(value.numberValue != 1)
            }
            if field.key == "ABL" {
                return .bool(value.numberValue > 0)
            }
            if field.key == "WS" {
                return .bool(!value.boolValue)
            }
            if field.key == "CF" {
                return .bool(!value.boolValue)
            }
            return .bool(value.boolValue)
        case .number:
            return .number(value.numberValue)
        case .select:
            return .string(value.stringValue)
        case .text, .secret, .file:
            return .string(value.stringValue)
        }
    }

    private func encodeValue(_ value: WLEDSettingValue, field: WLEDSettingDescriptor, draft: WLEDSettingsDraft) -> WLEDSettingValue {
        switch field.key {
        case "GC", "GB":
            let gamma = draft.values["GV"]?.numberValue ?? 2.2
            return value.boolValue ? .number(gamma) : .number(1)
        case "ABL":
            if value.boolValue {
                let currentLimit = draft.values["MA"]?.numberValue ?? draft.originalValues["MA"]?.numberValue ?? 0
                return .number(currentLimit > 0 ? currentLimit : 850)
            }
            return .number(0)
        case "WS":
            return .bool(!value.boolValue)
        case "CF":
            return .bool(!value.boolValue)
        case "CM" where draft.category.id == "wifi-network":
            return .string(normalizeMDNSName(value.stringValue))
        default:
            switch field.control {
            case .toggle:
                return .bool(value.boolValue)
            case .number:
                return .number(value.numberValue)
            case .select:
                if Double(value.stringValue) != nil {
                    return .number(value.numberValue)
                }
                return .string(value.stringValue)
            case .text, .secret, .file:
                return .string(value.stringValue)
            }
        }
    }

    private func normalizeMDNSName(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.lowercased().hasPrefix("http://") {
            normalized.removeFirst("http://".count)
        } else if normalized.lowercased().hasPrefix("https://") {
            normalized.removeFirst("https://".count)
        }
        normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines))
        if normalized.lowercased().hasSuffix(".local") {
            normalized.removeLast(".local".count)
        }
        return normalized.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines))
    }

    private func secretConfigured(field: WLEDSettingDescriptor, in config: [String: Any]) -> Bool {
        if let path = field.configPath {
            let lengthPath = path.replacingOccurrences(of: ".psk", with: ".pskl")
                .replacingOccurrences(of: ".pwd", with: ".pskl")
            if WLEDSettingValue.fromJSON(resolve(path: lengthPath, in: config)).numberValue > 0 {
                return true
            }
        }
        return false
    }

    private func ledOutputs(from root: [String: Any]) -> [WLEDLEDOutput] {
        let hw = root["hw"] as? [String: Any]
        let led = hw?["led"] as? [String: Any] ?? [:]
        let outputs = led["ins"] as? [[String: Any]] ?? []
        return outputs.map { bus in
            let maxPowerMilliamps = intValue(bus["maxpwr"]) ?? 0
            return WLEDLEDOutput(
                type: intValue(bus["type"]) ?? 22,
                pins: pinString(from: bus["pin"]),
                length: intValue(bus["len"]) ?? 0,
                start: intValue(bus["start"]) ?? 0,
                skip: intValue(bus["skip"]) ?? 0,
                reverse: boolValue(bus["rev"]) ?? false,
                refreshWhenOff: boolValue(bus["ref"]) ?? false,
                colorOrder: unpackedColorOrder(from: intValue(bus["order"]) ?? intValue(bus["co"]) ?? 0).colorOrder,
                whiteChannelSwap: unpackedColorOrder(from: intValue(bus["order"]) ?? intValue(bus["co"]) ?? 0).whiteChannelSwap,
                autoWhiteMode: intValue(bus["rgbwm"]) ?? intValue(led["rgbwm"]) ?? 0,
                frequency: intValue(bus["freq"]) ?? 0,
                currentMilliamps: intValue(bus["ledma"]) ?? 55,
                maxPowerMilliamps: maxPowerMilliamps,
                driverType: intValue(bus["drv"]) ?? 0,
                perOutputLimiter: boolValue(bus["per"]) ?? (maxPowerMilliamps > 0)
            )
        }
    }

    private func defaultLEDOutput() -> WLEDLEDOutput {
        WLEDLEDOutput(
            type: 22,
            pins: "",
            length: 1,
            start: 0,
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

    private func colorOrderOverrides(from root: [String: Any]) -> [WLEDColorOrderOverride] {
        let hw = root["hw"] as? [String: Any] ?? [:]
        let entries = hw["com"] as? [[String: Any]] ?? []
        var seen: Set<String> = []
        return entries.compactMap { entry in
            let packed = unpackedColorOrder(from: intValue(entry["order"]) ?? 0)
            let override = WLEDColorOrderOverride(
                start: max(0, intValue(entry["start"]) ?? 0),
                length: max(1, intValue(entry["len"]) ?? 1),
                colorOrder: packed.colorOrder,
                whiteChannelSwap: packed.whiteChannelSwap
            )
            return seen.insert(override.normalizedSignature).inserted ? override : nil
        }
    }

    private func ledDiagnostics(from root: [String: Any], outputs: [WLEDLEDOutput]) -> WLEDLEDDiagnostics {
        let hw = root["hw"] as? [String: Any] ?? [:]
        let led = hw["led"] as? [String: Any] ?? [:]
        let totalLEDs = intValue(led["total"]) ?? outputs.reduce(0) { $0 + max(0, $1.length) }
        let totalMilliamps = outputs.reduce(0) { partial, output in
            partial + max(0, output.length) * max(0, output.currentMilliamps)
        }
        let brightestWhiteAmps = totalMilliamps > 0 ? ceil(Double(totalMilliamps) / 1000.0) : nil
        let typicalEffectsAmps = totalMilliamps > 0 ? Double(totalMilliamps) * 0.38 / 1000.0 : nil
        let estimatedMemoryUsed = totalLEDs > 0 ? 112 + (totalLEDs * 16) : nil
        let hardwareChannelsSummary = hardwareChannelsSummary(for: outputs)

        return WLEDLEDDiagnostics(
            totalLEDs: totalLEDs,
            brightestWhiteAmps: brightestWhiteAmps,
            typicalEffectsAmps: typicalEffectsAmps,
            estimatedMemoryUsedBytes: estimatedMemoryUsed,
            estimatedMemoryAvailableBytes: nil,
            hardwareChannelsSummary: hardwareChannelsSummary
        )
    }

    private func hardwareChannelsSummary(for outputs: [WLEDLEDOutput]) -> String? {
        let digitalOutputs = outputs.filter { output in
            ![42, 44, 45, 46].contains(output.type)
        }.count
        let i2sOutputs = outputs.filter { $0.driverType == 1 }.count
        guard digitalOutputs > 0 || i2sOutputs > 0 else { return nil }
        return "RMT \(max(0, digitalOutputs - i2sOutputs))/8, I2S \(i2sOutputs)/8"
    }

    private func unpackedColorOrder(from packed: Int) -> (colorOrder: Int, whiteChannelSwap: Int) {
        (packed & 0x0F, (packed >> 4) & 0x0F)
    }

    private func packedColorOrder(colorOrder: Int, whiteChannelSwap: Int) -> Int {
        max(0, min(colorOrder, 5)) | (max(0, min(whiteChannelSwap, 4)) << 4)
    }

    private func normalizedPinString(_ value: String) -> String {
        value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ",")
    }

    private func formIndexSuffix(_ index: Int) -> String {
        if index < 10 {
            return String(index)
        }
        guard let base = Character("A").unicodeScalars.first,
              let scalar = UnicodeScalar(base.value + UInt32(index - 10)) else {
            return String(index)
        }
        return String(scalar)
    }

    private func ledSettingsFrequencyOption(type: Int, frequency: Int) -> Int {
        switch frequency {
        case 1_000: return 0
        case 2_000: return 1
        case 5_000: return 2
        case 10_000: return 3
        case 20_000: return 4
        case 9_765...9_766: return 0
        case 13_020...13_021: return 1
        case 19_531: return 2
        case 39_062: return 3
        case 65_000...65_535: return 4
        default: return 0
        }
    }

    private func formURLEncodedData(_ values: [(String, String)]) -> Data {
        values.map { key, value in
            "\(formURLEncode(key))=\(formURLEncode(value))"
        }
        .joined(separator: "&")
        .data(using: .utf8) ?? Data()
    }

    private func formURLEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: " ", with: "+") ?? value
    }

    private func formString(_ value: Any?) -> String {
        if let string = value as? String { return string }
        if let int = intValue(value) { return String(int) }
        if let double = doubleValue(value) { return String(double) }
        if let bool = boolValue(value) { return bool ? "1" : "0" }
        return ""
    }

    private func secretPlaceholder(configuredLength: Int) -> String {
        configuredLength > 0 ? "********" : ""
    }

    private func ipComponents(from value: Any?, fallback: [Int] = [0, 0, 0, 0]) -> [Int] {
        let values: [Int]
        if let array = value as? [Any] {
            values = array.compactMap(intValue)
        } else if let array = value as? [Int] {
            values = array
        } else {
            values = []
        }

        let padded = values + fallback
        return Array(padded.prefix(4))
    }

    private func addIPAddressFields(
        prefix: String,
        value: Any?,
        fallback: [Int] = [0, 0, 0, 0],
        into form: inout [(String, String)]
    ) {
        let components = ipComponents(from: value, fallback: fallback)
        for index in 0..<4 {
            form.append(("\(prefix)\(index)", formString(components[index])))
        }
    }

    private func pinString(from value: Any?) -> String {
        if let pins = value as? [Int] {
            return pins.map(String.init).joined(separator: ", ")
        }
        if let pins = value as? [Any] {
            return pins.compactMap(intValue).map(String.init).joined(separator: ", ")
        }
        if let pin = intValue(value) {
            return String(pin)
        }
        return ""
    }

    private func pinArray(from value: Any?) -> [Int] {
        if let pins = value as? [Int] {
            return pins
        }
        if let pins = value as? [Any] {
            return pins.compactMap(intValue)
        }
        if let pin = intValue(value) {
            return [pin]
        }
        return []
    }

    private func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(round(double)) }
        if let float = value as? Float { return Int(round(float)) }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let float = value as? Float { return Double(float) }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let int = value as? Int { return String(int) }
        if let double = value as? Double { return String(Int(round(double))) }
        if let float = value as? Float { return String(Int(round(float))) }
        return nil
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let int = intValue(value) { return int != 0 }
        if let string = value as? String {
            return ["true", "1", "yes", "on"].contains(string.lowercased())
        }
        return nil
    }

    // MARK: - JSON Path Helpers

    private enum PathComponent: Equatable {
        case key(String)
        case index(Int)
    }

    private func components(for path: String) -> [PathComponent] {
        path.split(separator: ".").flatMap { part -> [PathComponent] in
            var components: [PathComponent] = []
            let string = String(part)
            let key = string.split(separator: "[", maxSplits: 1).first.map(String.init) ?? string
            if !key.isEmpty {
                components.append(.key(key))
            }
            let matches = string.matches(of: /\[(\d+)\]/)
            for match in matches {
                if let index = Int(match.1) {
                    components.append(.index(index))
                }
            }
            return components
        }
    }

    private func resolve(path: String, in object: [String: Any]) -> Any? {
        let pathComponents = components(for: path)
        var current: Any? = object
        for component in pathComponents {
            switch component {
            case .key(let key):
                current = (current as? [String: Any])?[key]
            case .index(let index):
                current = (current as? [Any]).flatMap { array in
                    array.indices.contains(index) ? array[index] : nil
                }
            }
        }
        return current
    }

    private func set(_ value: WLEDSettingValue, at path: String, in object: inout [String: Any]) {
        var pathComponents = components(for: path)
        guard !pathComponents.isEmpty else { return }
        set(value.jsonCompatibleValue, components: &pathComponents, in: &object)
    }

    private func set(_ value: Any, components: inout [PathComponent], in object: inout [String: Any]) {
        guard let component = components.first else { return }
        components.removeFirst()

        guard case .key(let key) = component else { return }
        if components.isEmpty {
            object[key] = value
            return
        }

        if case .index(let index) = components.first {
            components.removeFirst()
            var array = object[key] as? [Any] ?? []
            while array.count <= index {
                array.append([String: Any]())
            }
            if components.isEmpty {
                array[index] = value
            } else {
                var child = array[index] as? [String: Any] ?? [:]
                set(value, components: &components, in: &child)
                array[index] = child
            }
            object[key] = array
        } else {
            var child = object[key] as? [String: Any] ?? [:]
            set(value, components: &components, in: &child)
            object[key] = child
        }
    }
}
