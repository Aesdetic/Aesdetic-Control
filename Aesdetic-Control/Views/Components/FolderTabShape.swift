import SwiftUI

/// A custom shape that draws a card with a folder-tab "bump" at the top for the active tab
struct FolderTabShape: Shape {
    var activeTabIndex: Int
    var tabCount: Int
    var tabHeight: CGFloat
    var cornerRadius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let width = rect.width
        let height = rect.height
        let cardTop = tabHeight
        
        // Calculate tab dimensions
        let tabWidth = width / CGFloat(tabCount)
        let tabStartX = CGFloat(activeTabIndex) * tabWidth
        let tabEndX = tabStartX + tabWidth
        
        // Start from bottom-left corner (with radius)
        path.move(to: CGPoint(x: 0, y: height - cornerRadius))
        
        // Bottom-left corner
        path.addArc(
            center: CGPoint(x: cornerRadius, y: height - cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(90),
            clockwise: true
        )
        
        // Bottom edge
        path.addLine(to: CGPoint(x: width - cornerRadius, y: height))
        
        // Bottom-right corner
        path.addArc(
            center: CGPoint(x: width - cornerRadius, y: height - cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(0),
            clockwise: true
        )
        
        // Right edge going up
        path.addLine(to: CGPoint(x: width, y: cardTop + cornerRadius))
        
        // Top-right corner of card
        if activeTabIndex == tabCount - 1 {
            // Active tab is the rightmost: no corner here, continue to tab
            path.addLine(to: CGPoint(x: width, y: cornerRadius))
        } else {
            // Add rounded corner
            path.addArc(
                center: CGPoint(x: width - cornerRadius, y: cardTop + cornerRadius),
                radius: cornerRadius,
                startAngle: .degrees(0),
                endAngle: .degrees(-90),
                clockwise: true
            )
            path.addLine(to: CGPoint(x: tabEndX, y: cardTop))
        }
        
        // Right side of active tab going up
        path.addLine(to: CGPoint(x: tabEndX, y: cornerRadius))
        
        // Top-right corner of tab
        path.addArc(
            center: CGPoint(x: tabEndX - cornerRadius, y: cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(-90),
            clockwise: true
        )
        
        // Top edge of tab
        path.addLine(to: CGPoint(x: tabStartX + cornerRadius, y: 0))
        
        // Top-left corner of tab
        path.addArc(
            center: CGPoint(x: tabStartX + cornerRadius, y: cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-180),
            clockwise: true
        )
        
        // Left side of tab going down
        path.addLine(to: CGPoint(x: tabStartX, y: cardTop))
        
        // Top-left corner of card
        if activeTabIndex == 0 {
            // Active tab is the leftmost: no corner here, continue down
            path.addLine(to: CGPoint(x: 0, y: cardTop + cornerRadius))
        } else {
            // Line to where corner starts
            path.addLine(to: CGPoint(x: cornerRadius, y: cardTop))
            // Add rounded corner
            path.addArc(
                center: CGPoint(x: cornerRadius, y: cardTop + cornerRadius),
                radius: cornerRadius,
                startAngle: .degrees(-90),
                endAngle: .degrees(-180),
                clockwise: true
            )
        }
        
        // Left edge going down to bottom-left corner
        path.addLine(to: CGPoint(x: 0, y: height - cornerRadius))
        
        // Path automatically closes back to start point
        path.closeSubpath()
        
        return path
    }
}

