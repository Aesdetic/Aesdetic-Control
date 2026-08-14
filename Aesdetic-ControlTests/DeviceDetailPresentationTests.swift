import CoreGraphics
import Testing
@testable import Aesdetic_Control

struct DeviceDetailPresentationTests {
    @Test("expanded panel keeps an eight-point physical bottom gutter across safe-area classes")
    func physicalBottomGutter() {
        let layouts: [(size: CGSize, bottomSafeAreaInset: CGFloat)] = [
            (CGSize(width: 375, height: 667), 0),   // Compact, square-corner iPhone
            (CGSize(width: 393, height: 818), 34),  // Dynamic Island iPhone
            (CGSize(width: 430, height: 898), 34),  // Max-size Dynamic Island iPhone
            (CGSize(width: 1024, height: 1346), 20) // Home-indicator iPad
        ]

        for layout in layouts {
            let frame = DeviceDetailPresentation.expandedPanelFrame(
                in: layout.size,
                bottomSafeAreaInset: layout.bottomSafeAreaInset
            )

            #expect(
                frame.maxY
                    == layout.size.height
                    + layout.bottomSafeAreaInset
                    - DeviceDetailPresentation.expandedPanelBottomInset
            )
        }
    }

    @Test("fallback bottom radius adapts to rounded-screen safe areas")
    func adaptiveFallbackBottomRadius() {
        let compactRadius = DeviceDetailPresentation.bottomCornerRadius(
            sourceFrame: nil,
            progress: 1,
            bottomSafeAreaInset: 0
        )
        let dynamicIslandRadius = DeviceDetailPresentation.bottomCornerRadius(
            sourceFrame: nil,
            progress: 1,
            bottomSafeAreaInset: 34
        )
        let iPadRadius = DeviceDetailPresentation.bottomCornerRadius(
            sourceFrame: nil,
            progress: 1,
            bottomSafeAreaInset: 20
        )

        #expect(compactRadius == DeviceDetailPresentation.expandedBottomCornerRadiusMinimum)
        #expect(dynamicIslandRadius == 48)
        #expect(iPadRadius == DeviceDetailPresentation.expandedBottomCornerRadiusMinimum)
    }

    @Test("expanded top radius is raised without changing the bottom minimum")
    func raisedTopRadius() {
        let expandedTopRadius = DeviceDetailPresentation.cornerRadius(
            sourceFrame: nil,
            progress: 1
        )
        let compactBottomRadius = DeviceDetailPresentation.bottomCornerRadius(
            sourceFrame: nil,
            progress: 1,
            bottomSafeAreaInset: 0
        )

        #expect(expandedTopRadius == 36)
        #expect(compactBottomRadius == 34)
    }

    @Test("adaptive bottom radius remains continuous through the detail morph")
    func adaptiveRadiusMorph() {
        let collapsedRadius = DeviceDetailPresentation.bottomCornerRadius(
            sourceFrame: nil,
            progress: 0,
            bottomSafeAreaInset: 34
        )
        let midpointRadius = DeviceDetailPresentation.bottomCornerRadius(
            sourceFrame: nil,
            progress: 0.5,
            bottomSafeAreaInset: 34
        )
        let expandedRadius = DeviceDetailPresentation.bottomCornerRadius(
            sourceFrame: nil,
            progress: 1,
            bottomSafeAreaInset: 34
        )

        #expect(collapsedRadius == DeviceDetailPresentation.folderSourceCornerRadius)
        #expect(midpointRadius > collapsedRadius)
        #expect(midpointRadius < expandedRadius)
    }
}
