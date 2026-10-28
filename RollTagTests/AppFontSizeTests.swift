import XCTest
@testable import RollTag

final class AppFontSizeTests: XCTestCase {
    func testClampsToAllowedSteps() {
        XCTAssertEqual(AppFontSize.clamped(-8), AppFontSize.minStep)
        XCTAssertEqual(AppFontSize.clamped(0), AppFontSize.defaultStep)
        XCTAssertEqual(AppFontSize.clamped(9), AppFontSize.maxStep)
    }

    func testPointsChangeTextSizeNotThumbnails() {
        XCTAssertEqual(AppFontSize.points(0), AppFontSize.defaultPoints)
        XCTAssertEqual(AppFontSize.points(1), AppFontSize.defaultPoints + 2)
        XCTAssertEqual(AppFontSize.points(-1), AppFontSize.defaultPoints - 2)
        XCTAssertGreaterThan(AppFontSize.points(3), AppFontSize.points(0))
        XCTAssertLessThan(AppFontSize.points(-2), AppFontSize.points(0))
    }
}
