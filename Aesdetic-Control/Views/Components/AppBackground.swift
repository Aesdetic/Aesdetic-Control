import SwiftUI
import UIKit

// Singleton to cache and preload background image
@MainActor
class BackgroundImageCache: ObservableObject {
    static let shared = BackgroundImageCache()
    
    @Published private(set) var cachedImage: UIImage?
    
    private init() {
        // Preload immediately on initialization
        preloadImage()
    }
    
    func preloadImage() {
        // Load image from assets on background thread
        DispatchQueue.global(qos: .userInitiated).async {
            if let image = UIImage(named: "LightTheme_Background") {
                DispatchQueue.main.async {
                    self.cachedImage = image
                    print("✅ Background image preloaded and cached")
                }
            }
        }
    }
}

struct AppBackground: View {
    @StateObject private var cache = BackgroundImageCache.shared
    
    var body: some View {
        if let uiImage = cache.cachedImage {
            // Use cached UIImage directly (no loading delay)
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .allowsHitTesting(false)
        } else {
            // Fallback to asset name while preloading
            Image("LightTheme_Background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}


