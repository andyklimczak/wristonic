import XCTest
@testable import wristonic_Watch_App

final class AlbumSortModeTests: XCTestCase {
    func testDisplayNamesMatchExpectedLabels() {
        XCTAssertEqual(AlbumSortMode.alphabeticalByName.displayName, "Name")
        XCTAssertEqual(AlbumSortMode.random.displayName, "Random")
        XCTAssertEqual(AlbumSortMode.recentlyAdded.displayName, "Recently Added")
        XCTAssertEqual(AlbumSortMode.recentlyPlayed.displayName, "Recently Played")
        XCTAssertEqual(AlbumSortMode.mostPlayed.displayName, "Most Played")
    }

    func testSubsonicTypeMappingMatchesServerExpectations() {
        XCTAssertEqual(AlbumSortMode.alphabeticalByName.subsonicType, "alphabeticalByName")
        XCTAssertEqual(AlbumSortMode.random.subsonicType, "random")
        XCTAssertEqual(AlbumSortMode.recentlyAdded.subsonicType, "newest")
        XCTAssertEqual(AlbumSortMode.recentlyPlayed.subsonicType, "recent")
        XCTAssertEqual(AlbumSortMode.mostPlayed.subsonicType, "frequent")
    }

    func testArtistAlbumSortOrdersByNameAndYear() {
        let albums = [
            album(id: "c", name: "Charlie", year: nil),
            album(id: "a", name: "Alpha", year: 2024),
            album(id: "b", name: "Bravo", year: 2020),
            album(id: "d", name: "Delta", year: 2024)
        ]

        XCTAssertEqual(ArtistAlbumSortMode.name.sorted(albums).map(\.id), ["a", "b", "c", "d"])
        XCTAssertEqual(ArtistAlbumSortMode.oldestToNewest.sorted(albums).map(\.id), ["b", "a", "d", "c"])
        XCTAssertEqual(ArtistAlbumSortMode.newestToOldest.sorted(albums).map(\.id), ["a", "d", "b", "c"])
    }

    private func album(id: String, name: String, year: Int?) -> AlbumSummary {
        AlbumSummary(
            id: id,
            name: name,
            artistID: "artist-1",
            artistName: "Artist",
            coverArtID: nil,
            songCount: 1,
            duration: nil,
            year: year,
            createdAt: nil
        )
    }
}
