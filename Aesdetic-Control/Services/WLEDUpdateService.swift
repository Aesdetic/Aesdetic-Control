//
//  WLEDUpdateService.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 2/6/26.
//

import Foundation

final class WLEDUpdateService {
    static let shared = WLEDUpdateService()

    private let urlSession: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8.0
        config.timeoutIntervalForResource = 20.0
        self.urlSession = URLSession(configuration: config)
    }

    func fetchLatestStableVersion() async throws -> String {
        guard let url = URL(string: "https://api.github.com/repos/wled/WLED/releases/latest") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Aesdetic-Control", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        return VersionComparator.normalize(release.tagName)
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
    }
}

enum VersionComparator {
    static func normalize(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    static func compare(_ current: String, _ latest: String) -> ComparisonResult {
        let currentParts = numericParts(from: normalize(current))
        let latestParts = numericParts(from: normalize(latest))

        let maxCount = max(currentParts.count, latestParts.count)
        for index in 0..<maxCount {
            let currentValue = index < currentParts.count ? currentParts[index] : 0
            let latestValue = index < latestParts.count ? latestParts[index] : 0
            if currentValue < latestValue { return .orderedAscending }
            if currentValue > latestValue { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func numericParts(from version: String) -> [Int] {
        let base = version.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true).first ?? Substring("")
        return base.split(separator: ".").map { Int($0) ?? 0 }
    }
}
