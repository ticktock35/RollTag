import XCTest
@testable import RollTag

final class ScanProgressTests: XCTestCase {
    func testIdentifyingPercentFollowsFileCountNotWeightedOverall() {
        let progress = ScanProgress(
            warehouseName: "Travel",
            warehouseID: UUID(),
            phase: .identifying,
            currentFile: "a.jpg",
            completed: 7075,
            total: 7204
        )
        XCTAssertEqual(progress.percentInt, 98)
        XCTAssertEqual(progress.displayFraction ?? 0, 7075.0 / 7204.0, accuracy: 0.0001)
        XCTAssertTrue(progress.showsPercent)
    }

    func testScanningUsesKnownCountAsEstimate() {
        let progress = ScanProgress(
            warehouseName: "Travel",
            warehouseID: UUID(),
            phase: .scanning,
            currentFile: "export/clip.mp3",
            completed: 7200,
            total: 7204
        )
        XCTAssertTrue(progress.showsPercent)
        XCTAssertEqual(progress.percentInt, 99)
        XCTAssertFalse(progress.isScanningPastEstimate)
    }

    func testScanningNeverShowsHundredPercentUntilFinished() {
        let progress = ScanProgress(
            warehouseName: "Travel",
            warehouseID: UUID(),
            phase: .scanning,
            currentFile: "export/clip.mov",
            completed: 7204,
            total: 7204
        )
        XCTAssertEqual(progress.percentInt, 99)
        XCTAssertTrue(progress.isScanningPastEstimate)
        XCTAssertEqual(progress.displayFraction ?? 0, 0.99, accuracy: 0.0001)
    }

    func testScanningWithoutTotalHidesPercent() {
        let progress = ScanProgress(
            warehouseName: "Travel",
            warehouseID: UUID(),
            phase: .scanning,
            currentFile: "folder",
            completed: 40,
            total: 0
        )
        XCTAssertFalse(progress.showsPercent)
        XCTAssertNil(progress.displayFraction)
    }
}
