import SwiftUI
import UIKit

enum AppBackgroundChoice: String, CaseIterable, Identifiable {
    case blueHour6
    case sunrise
    case sunset
    case alpine
    case blueHour5
    case blueHour4
    case blueHour
    case neutral
    case custom

    var id: String { rawValue }

    static let defaultChoice: AppBackgroundChoice = .blueHour6

    var title: String {
        switch self {
        case .blueHour6:
            return "Blue Hour"
        case .sunrise:
            return "Sunrise"
        case .sunset:
            return "Sunset"
        case .alpine:
            return "Alpine"
        case .blueHour5:
            return "Dusk"
        case .blueHour4:
            return "Mist"
        case .blueHour:
            return "Classic"
        case .neutral:
            return "Clean"
        case .custom:
            return "My Photo"
        }
    }

    var assetName: String? {
        switch self {
        case .blueHour6:
            return "BlueHour6AppBackground"
        case .sunrise:
            return "SunriseHourAppBackground"
        case .sunset:
            return "SunsetHourAppBackground"
        case .alpine:
            return "AlpinePhotoBackground"
        case .blueHour5:
            return "BlueHour5AppBackground"
        case .blueHour4:
            return "BlueHour4AppBackground"
        case .blueHour:
            return "BlueHourAppBackground"
        case .neutral, .custom:
            return nil
        }
    }

    var usesPhotoLayer: Bool {
        switch self {
        case .neutral:
            return false
        case .custom:
            return AppBackgroundPreference.customBackgroundExists
        default:
            return assetName != nil
        }
    }

    static var suggestedChoices: [AppBackgroundChoice] {
        [.blueHour6, .sunrise, .sunset, .alpine, .blueHour5, .blueHour4, .blueHour, .neutral]
    }
}

enum AppBackgroundPreference {
    static let selectedChoiceKey = "AppBackground.choice"
    static let customVersionKey = "AppBackground.customVersion"

    private static let directoryName = "Appearance"
    private static let customFileName = "custom-app-background.jpg"

    static var customBackgroundURL: URL {
        applicationSupportDirectory
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(customFileName)
    }

    static var customBackgroundExists: Bool {
        FileManager.default.fileExists(atPath: customBackgroundURL.path)
    }

    static func image(for choice: AppBackgroundChoice) -> UIImage? {
        switch choice {
        case .custom:
            return UIImage(contentsOfFile: customBackgroundURL.path)
        case .neutral:
            return nil
        default:
            guard let assetName = choice.assetName else { return nil }
            return UIImage(named: assetName)
        }
    }

    static func saveCustomBackground(from data: Data) throws {
        guard let image = UIImage(data: data) else {
            throw AppBackgroundImageError.unreadableImage
        }

        let preparedImage = prepareBackgroundImage(image)
        guard let encoded = preparedImage.jpegData(compressionQuality: 0.86) else {
            throw AppBackgroundImageError.encodingFailed
        }

        let directory = customBackgroundURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoded.write(to: customBackgroundURL, options: .atomic)
    }

    static func deleteCustomBackground() {
        try? FileManager.default.removeItem(at: customBackgroundURL)
    }

    private static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private static func prepareBackgroundImage(_ image: UIImage) -> UIImage {
        let maxDimension: CGFloat = 1800
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return image }

        let scale = min(1, maxDimension / max(sourceSize.width, sourceSize.height))
        let outputSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: outputSize))
            image.draw(in: CGRect(origin: .zero, size: outputSize))
        }
    }
}

enum AppBackgroundImageError: LocalizedError {
    case unreadableImage
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "That photo could not be read."
        case .encodingFailed:
            return "That photo could not be prepared."
        }
    }
}
