import CoreGraphics

enum ResultShelfLayoutMetrics {
    static let itemWidth: CGFloat = 112
    static let itemHeight: CGFloat = 96
    static let itemSpacing: CGFloat = 8
    static let minimumHorizontalInset: CGFloat = 6
    static let scrollViewHeight: CGFloat = 112

    static func contentWidth(itemCount: Int) -> CGFloat {
        guard itemCount > 0 else { return 0 }
        return (CGFloat(itemCount) * itemWidth)
            + (CGFloat(itemCount - 1) * itemSpacing)
    }

    static func leadingInset(viewportWidth: CGFloat, itemCount: Int) -> CGFloat {
        guard itemCount > 0 else { return minimumHorizontalInset }
        let centered = (viewportWidth - contentWidth(itemCount: itemCount)) / 2
        return max(minimumHorizontalInset, centered)
    }

    static func overflows(viewportWidth: CGFloat, itemCount: Int) -> Bool {
        contentWidth(itemCount: itemCount) + (minimumHorizontalInset * 2) > viewportWidth
    }
}
