import CoreGraphics

struct IslandScreenGeometry: Equatable, Sendable {
    let frame: CGRect
    let visibleFrame: CGRect
    let safeAreaTop: CGFloat
    let auxiliaryTopLeftArea: CGRect?
    let auxiliaryTopRightArea: CGRect?

    var physicalNotchFrame: CGRect? {
        guard let left = auxiliaryTopLeftArea,
              let right = auxiliaryTopRightArea else { return nil }

        guard safeAreaTop > 0 else { return nil }

        let notch = CGRect(
            x: left.maxX,
            y: frame.maxY - safeAreaTop,
            width: right.minX - left.maxX,
            height: safeAreaTop
        )
        guard notch.width > 0, notch.height > 0 else { return nil }

        let clipped = notch.intersection(frame)
        return clipped.isNull || clipped.isEmpty ? nil : clipped
    }
}

enum IslandLayout {
    static let topGap: CGFloat = 8
    static let horizontalMargin: CGFloat = 16
    static let compactWingToNotchHeightRatio: CGFloat = 1.5
    static let compactLipToNotchHeightRatio: CGFloat = 0.1
    static let maximumCompactLipHeight: CGFloat = 3

    static func preferredSize(for mode: IslandLayoutMode) -> CGSize {
        switch mode {
        case .compact:
            CGSize(width: 168, height: 38)
        case .expanded:
            CGSize(width: 380, height: 124)
        case .expandedActions:
            CGSize(width: 536, height: 188)
        case .compactProgress:
            CGSize(width: 400, height: 58)
        }
    }

    static func frame(
        in geometry: IslandScreenGeometry,
        mode: IslandLayoutMode,
        topGap: CGFloat = IslandLayout.topGap
    ) -> CGRect {
        if let notchFrame = geometry.physicalNotchFrame {
            return physicalNotchFrame(
                screenFrame: geometry.frame,
                notchFrame: notchFrame,
                mode: mode
            )
        }

        return floatingFrame(
            in: geometry.visibleFrame,
            mode: mode,
            topGap: topGap
        )
    }

    private static func physicalNotchFrame(
        screenFrame: CGRect,
        notchFrame: CGRect,
        mode: IslandLayoutMode
    ) -> CGRect {
        if mode == .compact {
            let wingWidth = notchFrame.height * compactWingToNotchHeightRatio
            let lipHeight = min(
                notchFrame.height * compactLipToNotchHeightRatio,
                maximumCompactLipHeight
            )
            let preferredWidth = notchFrame.width + (wingWidth * 2)
            let maximumWidth = max(1, screenFrame.width - (horizontalMargin * 2))
            let width = min(preferredWidth, maximumWidth)
            let height = notchFrame.height + lipHeight

            return CGRect(
                x: screenFrame.midX - (width / 2),
                y: screenFrame.maxY - height,
                width: width,
                height: height
            )
        }

        let preferred = preferredSize(for: mode)
        let maximumWidth = max(1, screenFrame.width - (horizontalMargin * 2))
        let width = min(preferred.width, maximumWidth)
        let height = min(preferred.height + notchFrame.height, screenFrame.height)

        return CGRect(
            x: screenFrame.midX - (width / 2),
            y: screenFrame.maxY - height,
            width: width,
            height: height
        )
    }

    private static func floatingFrame(
        in availableFrame: CGRect,
        mode: IslandLayoutMode,
        topGap: CGFloat
    ) -> CGRect {
        let preferred = preferredSize(for: mode)
        let maximumWidth = max(1, availableFrame.width - (horizontalMargin * 2))
        let width = min(preferred.width, maximumWidth)
        let height = min(preferred.height, max(1, availableFrame.height - topGap))
        let origin = CGPoint(
            x: availableFrame.midX - (width / 2),
            y: availableFrame.maxY - topGap - height
        )

        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }
}
