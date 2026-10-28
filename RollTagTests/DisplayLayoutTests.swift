import XCTest
@testable import RollTag

final class DisplayLayoutTests: XCTestCase {
    private let builtIn = DisplayLayout.Screen(
        id: 1,
        name: "Built-in Retina Display",
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
        isBuiltIn: true
    )
    private let external = DisplayLayout.Screen(
        id: 2,
        name: "PHL 325M8C",
        frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1512, y: 0, width: 2560, height: 1400),
        isBuiltIn: false
    )

    func testEmptyScreenList() {
        XCTAssertTrue(DisplayLayout.screens(from: []).isEmpty)
        XCTAssertNil(DisplayLayout.defaultPrimaryID(libraryScreenID: nil, screens: []))
    }

    func testCounterpartIsTheOtherScreen() {
        let pair = [builtIn, external]
        XCTAssertEqual(DisplayLayout.counterpart(to: 1, in: pair)?.id, 2)
        XCTAssertEqual(DisplayLayout.counterpart(to: 2, in: pair)?.id, 1)
        XCTAssertNil(DisplayLayout.counterpart(to: 1, in: [builtIn]))
        XCTAssertEqual(DisplayLayout.counterpart(to: nil, in: pair)?.id, 2)
    }

    func testDefaultPrimaryIsTheScreenThatIsNotTheLibrary() {
        let pair = [builtIn, external]
        XCTAssertEqual(DisplayLayout.defaultPrimaryID(libraryScreenID: 1, screens: pair), 2)
        XCTAssertEqual(DisplayLayout.defaultPrimaryID(libraryScreenID: 2, screens: pair), 1)
        XCTAssertEqual(DisplayLayout.defaultPrimaryID(libraryScreenID: nil, screens: pair), 2)
        XCTAssertEqual(DisplayLayout.defaultPrimaryID(libraryScreenID: 1, screens: [builtIn]), 1)
    }

    func testScreenLookupIgnoresMissingIDs() {
        let pair = [builtIn, external]
        XCTAssertEqual(DisplayLayout.screen(id: 2, in: pair)?.name, "PHL 325M8C")
        XCTAssertNil(DisplayLayout.screen(id: 9, in: pair))
        XCTAssertNil(DisplayLayout.screen(id: nil, in: pair))
    }
}
