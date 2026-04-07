import XCTest
@testable import wristonic_Watch_App

final class AlbumSortModeTests: XCTestCase {
    func testDisplayNamesMatchExpectedLabels() {
        XCTAssertEqual(AlbumSortMode.alphabeticalByName.displayName, "Name")
        XCTAssertEqual(AlbumSortMode.random.displayName, "Random")
        XCTAssertEqual(AlbumSortMode.recentlyAdded.displayName, "Recently Added")
        XCTAssertEqual(AlbumSortMode.recentlyPlayed.displayName, "Recently Played")
    }

    func testSubsonicTypeMappingMatchesServerExpectations() {
        XCTAssertEqual(AlbumSortMode.alphabeticalByName.subsonicType, "alphabeticalByName")
        XCTAssertEqual(AlbumSortMode.random.subsonicType, "random")
        XCTAssertEqual(AlbumSortMode.recentlyAdded.subsonicType, "newest")
        XCTAssertEqual(AlbumSortMode.recentlyPlayed.subsonicType, "recent")
    }
}
