import SwiftUI

struct ErrorBanner: View {
    let message: String
    var icon: String = "exclamationmark.triangle.fill"
    var actionTitle: String?
    var onAction: (() -> Void)?
    var onDismiss: () -> Void
    
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme
    
    private var announcement: String {
        if let actionTitle { return "Error: \(message). Action: \(actionTitle)" }
        return "Error: \(message)"
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(AppTypography.role(.cardTitle))
                .foregroundColor(AppTheme.text(.glassPrimary, for: colorScheme))
                .padding(7)
                .background(
                    Circle()
                        .fill(AppTheme.statusAccent(.error, for: colorScheme).opacity(accentOpacity))
                )
                .accessibilityHidden(true)
            
            Text(message)
                .font(AppTypography.role(.bodyStrong))
                .foregroundColor(AppTheme.text(.glassPrimary, for: colorScheme))
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
                .accessibilityLabel("Error message")
                .accessibilityValue(message)
            
            Spacer(minLength: 12)
            
            if let actionTitle, let onAction {
                Button(actionTitle) {
                    onAction()
                }
                .buttonStyle(.borderedProminent)
                .tint(actionButtonTint)
                .foregroundColor(AppTheme.text(.glassPrimary, for: colorScheme))
                .clipShape(Capsule())
                .accessibilityLabel(actionTitle)
            }
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(AppTypography.role(.micro))
                    .foregroundColor(AppTheme.text(.glassSecondary, for: colorScheme).opacity(closeIconOpacity))
                    .padding(8)
                    .background(
                        Circle()
                            .fill(closeButtonBackground)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(bannerBackground)
                .shadow(color: bannerShadow, radius: 16, x: 0, y: 12)
        )
        .appLiquidGlass(role: .highContrast, cornerRadius: 16, highContrastDarkTintOpacity: colorScheme == .dark ? 0.16 : 0.06)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(announcement)
    }
}

struct ErrorBanner_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ErrorBanner(message: "Unable to reach WLED device. Check your Wi-Fi connection.") {
                // dismiss
            }
            ErrorBanner(message: "WLED timed out while saving preset.", actionTitle: "Retry", onAction: {}, onDismiss: {})
        }
        .padding()
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
}


private extension ErrorBanner {
    var bannerBackground: Color {
        Color.white.opacity(colorSchemeContrast == .increased ? 0.16 : 0.08)
    }
    
    var bannerShadow: Color {
        Color.black.opacity(colorSchemeContrast == .increased ? 0.45 : 0.35)
    }
    
    var actionButtonTint: Color {
        colorSchemeContrast == .increased ? Color.white.opacity(0.34) : Color.white.opacity(0.22)
    }
    
    var closeIconOpacity: Double {
        colorSchemeContrast == .increased ? 1.0 : 0.8
    }
    
    var closeButtonBackground: Color {
        Color.white.opacity(colorSchemeContrast == .increased ? 0.18 : 0.08)
    }

    var accentOpacity: Double {
        colorSchemeContrast == .increased ? 0.34 : 0.24
    }
}
