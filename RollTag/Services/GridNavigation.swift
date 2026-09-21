import CoreGraphics

enum GridNavigation {
    enum Direction: Equatable {
        case left
        case right
        case up
        case down
    }

    static let cellMinimum: CGFloat = 180
    static let spacing: CGFloat = 10
    static let rowSpacing: CGFloat = 18
    static let horizontalPadding: CGFloat = 8

    static func columnCount(
        width: CGFloat,
        cellMinimum: CGFloat = cellMinimum,
        spacing: CGFloat = spacing,
        horizontalPadding: CGFloat = horizontalPadding
    ) -> Int {
        let inner = max(0, width - horizontalPadding * 2)
        return max(1, Int((inner + spacing) / (cellMinimum + spacing)))
    }

    static func index(
        moving direction: Direction,
        from index: Int,
        count: Int,
        columns: Int
    ) -> Int? {
        guard count > 0, index >= 0, index < count else { return nil }
        let columns = max(1, columns)
        switch direction {
        case .left:
            let next = index - 1
            return next >= 0 ? next : nil
        case .right:
            let next = index + 1
            return next < count ? next : nil
        case .up:
            let next = index - columns
            return next >= 0 ? next : nil
        case .down:
            let next = index + columns
            return next < count ? next : nil
        }
    }

    static func linearIndex(moving delta: Int, from index: Int, count: Int) -> Int? {
        let next = index + delta
        guard next >= 0, next < count else { return nil }
        return next
    }

    static func firstPresentableIndex(
        moving delta: Int,
        from index: Int,
        count: Int,
        isPresentable: (Int) -> Bool
    ) -> Int? {
        var current = index
        while let next = linearIndex(moving: delta, from: current, count: count) {
            if isPresentable(next) { return next }
            current = next
        }
        return nil
    }
}
