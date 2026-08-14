import SwiftUI

struct RootContainer: View {
    @AppStorage("AppAppearance.selection") private var appearanceSelection = AppAppearance.system.rawValue

    var body: some View {
        ContentView()
            .preferredColorScheme(appAppearance.colorScheme)
            .symbolRenderingMode(.monochrome)
    }

    private var appAppearance: AppAppearance {
        AppAppearance(rawValue: appearanceSelection) ?? .system
    }
}
