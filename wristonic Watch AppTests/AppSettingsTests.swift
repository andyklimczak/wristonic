import XCTest
@testable import wristonic_Watch_App

final class AppSettingsTests: XCTestCase {
    func testMissingInternetRadioSettingDefaultsToVisible() throws {
        let data = Data("""
        {
          "serverURLString": "https://demo.navidrome.local",
          "username": "demo",
          "preferredBitrateKbps": 192,
          "allowInsecureConnections": false,
          "storageCapGB": 8,
          "offlineOnly": false
        }
        """.utf8)

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertTrue(settings.showInternetRadio)
        XCTAssertTrue(settings.showPlaylists)
        XCTAssertTrue(settings.showShuffle)
        XCTAssertEqual(settings.albumSortMode, .alphabeticalByName)
        XCTAssertEqual(settings.artistAlbumSortMode, .oldestToNewest)
        XCTAssertFalse(settings.isRepeatingAlbum)
        XCTAssertFalse(settings.isShuffleEnabled)
    }

    func testAlbumSortModeDecodesWhenPresent() throws {
        let data = Data("""
        {
          "albumSortMode": "recentlyPlayed"
        }
        """.utf8)

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(settings.albumSortMode, .recentlyPlayed)
    }

    func testArtistAlbumSortModeDecodesWhenPresent() throws {
        let data = Data(#"{"artistAlbumSortMode":"newestToOldest"}"#.utf8)

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(settings.artistAlbumSortMode, .newestToOldest)
    }

    func testAlbumRepeatDecodesWhenPresent() throws {
        let data = Data("""
        {
          "isRepeatingAlbum": true
        }
        """.utf8)

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertTrue(settings.isRepeatingAlbum)
    }

    func testShuffleSettingDecodesWhenPresent() throws {
        let data = Data(#"{"isShuffleEnabled":true}"#.utf8)

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertTrue(settings.isShuffleEnabled)
    }

    func testCachedLibrarySnapshotDefaultsMissingInternetRadioStationsToEmpty() throws {
        let data = Data("""
        {
          "artists": [],
          "albumsBySort": {},
          "albumsByArtist": {},
          "albumDetails": {}
        }
        """.utf8)

        let snapshot = try JSONDecoder().decode(CachedLibrarySnapshot.self, from: data)

        XCTAssertEqual(snapshot.internetRadioStations, [])
        XCTAssertEqual(snapshot.playlists, [])
        XCTAssertEqual(snapshot.playlistDetails, [:])
    }
}
