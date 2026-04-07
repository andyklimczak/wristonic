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
    }
}
