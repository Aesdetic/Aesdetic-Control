import SwiftUI

enum DockTab: String, CaseIterable, Identifiable {
    case dashboard
    case devices
    case automation
    case wellness

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard:
            return "Dashboard"
        case .devices:
            return "Devices"
        case .automation:
            return "Automation"
        case .wellness:
            return "Wellness"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:
            return "square.grid.2x2"
        case .devices:
            return "lightbulb.2"
        case .automation:
            return "clock.arrow.2.circlepath"
        case .wellness:
            return "heart.text.square"
        }
    }

    var accent: Color {
        Color.white
    }

    var accessibilityHint: String {
        switch self {
        case .dashboard:
            return "Shows the dashboard overview."
        case .devices:
            return "Shows your devices and controls."
        case .automation:
            return "Shows automation routines and schedules."
        case .wellness:
            return "Shows wellness tools and insights."
        }
    }
}

struct DockBar: View {
    @Binding var selectedTab: DockTab
    @Namespace private var highlightNamespace
    private let dockCornerRadius: CGFloat = 36
    private let dockPadding: CGFloat = 10
    private let pillHeight: CGFloat = 58

    var body: some View {
        HStack(spacing: 6) {
            ForEach(DockTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    DockItemView(
                        tab: tab,
                        isActive: tab == selectedTab,
                        namespace: highlightNamespace,
                        pillCornerRadius: max(12, dockCornerRadius - dockPadding),
                        pillHeight: pillHeight
                    )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .sensorySelection(trigger: selectedTab)
                .accessibilityLabel(tab.title)
                .accessibilityHint(tab.accessibilityHint)
                .accessibilityAddTraits(tab == selectedTab ? .isSelected : [])
            }
        }
        .padding(.vertical, dockPadding)
        .padding(.horizontal, dockPadding)
        .background(DockCardBackground(cornerRadius: dockCornerRadius))
        .clipShape(RoundedRectangle(cornerRadius: dockCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}

private struct DockItemView: View {
    let tab: DockTab
    let isActive: Bool
    let namespace: Namespace.ID
    let pillCornerRadius: CGFloat
    let pillHeight: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: tab.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            Text(tab.title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: pillHeight)
        .foregroundColor(isActive ? .white : Color.white.opacity(0.6))
        .background {
            if isActive {
                let shape = RoundedRectangle(cornerRadius: pillCornerRadius, style: .continuous)
                shape
                    .fill(Color.white.opacity(0.18))
                    .overlay(
                        LinearGradient(
                            colors: [
                                tab.accent.opacity(0.28),
                                tab.accent.opacity(0.08),
                                Color.white.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(shape)
                    )
                    .overlay(
                        shape
                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                    )
                    .matchedGeometryEffect(id: "dock-active-pill", in: namespace)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}

private struct DockCardBackground: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let fillOpacity: Double = colorSchemeContrast == .increased ? 0.2 : 0.12
        let strokeOpacity: Double = colorSchemeContrast == .increased ? 0.32 : 0.2

        shape
            .fill(Color.white.opacity(fillOpacity))
            .overlay(
                shape
                    .strokeBorder(Color.white.opacity(strokeOpacity), lineWidth: 1)
            )
    }
}
