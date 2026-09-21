import XCTest
@testable import RollTag

final class GridNavigationTests: XCTestCase {
    func testColumnCountMatchesAdaptiveGrid() {
        XCTAssertEqual(GridNavigation.columnCount(width: 196), 1)
        XCTAssertEqual(GridNavigation.columnCount(width: 386), 2)
        XCTAssertEqual(GridNavigation.columnCount(width: 800), 4)
        XCTAssertEqual(GridNavigation.columnCount(width: 956), 5)
        XCTAssertEqual(GridNavigation.columnCount(width: 0), 1)
    }

    func testLeftAndRightStayOnVisualNeighbors() {
        XCTAssertEqual(GridNavigation.index(moving: .left, from: 5, count: 12, columns: 4), 4)
        XCTAssertEqual(GridNavigation.index(moving: .right, from: 5, count: 12, columns: 4), 6)
        XCTAssertNil(GridNavigation.index(moving: .left, from: 0, count: 12, columns: 4))
        XCTAssertNil(GridNavigation.index(moving: .right, from: 11, count: 12, columns: 4))
    }

    func testUpAndDownUseColumnCount() {
        XCTAssertEqual(GridNavigation.index(moving: .up, from: 5, count: 12, columns: 4), 1)
        XCTAssertEqual(GridNavigation.index(moving: .down, from: 5, count: 12, columns: 4), 9)
        XCTAssertNil(GridNavigation.index(moving: .up, from: 2, count: 12, columns: 4))
        XCTAssertNil(GridNavigation.index(moving: .down, from: 9, count: 12, columns: 4))
    }

    func testLeftFromStartOfRowGoesToPreviousRow() {
        XCTAssertEqual(GridNavigation.index(moving: .left, from: 4, count: 12, columns: 4), 3)
    }

    func testLinearStepSkipsUnpresentableClips() {
        XCTAssertEqual(GridNavigation.linearIndex(moving: 1, from: 2, count: 5), 3)
        XCTAssertEqual(GridNavigation.linearIndex(moving: -1, from: 0, count: 5), nil)
        XCTAssertEqual(GridNavigation.linearIndex(moving: 1, from: -1, count: 5), 0)
        let skipped = GridNavigation.firstPresentableIndex(
            moving: 1,
            from: 0,
            count: 4,
            isPresentable: { $0 != 1 && $0 != 2 }
        )
        XCTAssertEqual(skipped, 3)
        XCTAssertNil(
            GridNavigation.firstPresentableIndex(
                moving: -1,
                from: 0,
                count: 4,
                isPresentable: { _ in true }
            )
        )
    }
}
