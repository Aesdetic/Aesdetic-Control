import SwiftUI

struct AppBackground: View {
    var body: some View {
        Image("LightTheme_Background")
            .resizable()
            .scaledToFill()
            .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}


