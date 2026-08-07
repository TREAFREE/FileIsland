import SwiftUI

/// A top-attached silhouette with small outward shoulders and rounded lower
/// corners. It keeps the compact Island visually connected to the display
/// housing instead of reading as a pill floating below the menu bar.
struct TopAttachedIslandShape: Shape {
    func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }

        let shoulder = min(rect.height * 0.22, 6)
        let lowerRadius = min(rect.height * 0.48, 18)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - shoulder, y: rect.minY + shoulder),
            control: CGPoint(x: rect.maxX - shoulder, y: rect.minY)
        )
        path.addLine(
            to: CGPoint(x: rect.maxX - shoulder, y: rect.maxY - lowerRadius)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - shoulder - lowerRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX - shoulder, y: rect.maxY)
        )
        path.addLine(
            to: CGPoint(x: rect.minX + shoulder + lowerRadius, y: rect.maxY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + shoulder, y: rect.maxY - lowerRadius),
            control: CGPoint(x: rect.minX + shoulder, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + shoulder, y: rect.minY + shoulder))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control: CGPoint(x: rect.minX + shoulder, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
