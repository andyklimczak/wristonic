import XCTest
@testable import wristonic_Watch_App

@MainActor
final class LibraryRepositoryTests: XCTestCase {
    func testOfflineOnlyFiltersArtistsAndAlbumsFromDownloads() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let settingsStore = makeSettingsStore(name: UUID().uuidString, offlineOnly: true)
        let cacheStore = JSONFileStore<CachedLibrarySnapshot>(url: root.appendingPathComponent("cache.json"))
        let record = DownloadRecord(
            album: AlbumSummary(id: "album-1", name: "Analog Dawn", artistID: "artist-1", artistName: "Aurora Echo", coverArtID: nil, songCount: 2, duration: 420, year: 2024, createdAt: nil),
            tracks: [
                Track(id: "track-1", albumID: "album-1", title: "First Light", artistID: "artist-1", artistName: "Aurora Echo", albumName: "Analog Dawn", duration: 210, trackNumber: 1, discNumber: 1, contentType: "audio/mpeg", suffix: "mp3", path: nil)
            ],
            downloadedTracks: [
                DownloadedTrackRecord(trackID: "track-1", relativePath: "album-1/1-track-1.mp3", bytes: 1024)
            ],
            pinned: false,
            state: DownloadState(status: .downloaded, progress: 1, errorMessage: nil),
            downloadedAt: Date(),
            totalBytes: 1024,
            playCount: 1,
            lastPlayedAt: Date()
        )

        let repository = LibraryRepository(
            cacheStore: cacheStore,
            settingsStore: settingsStore,
            clientProvider: { try makeClient() },
            downloadRecordsProvider: { [record] }
        )

        let artists = try await repository.artists()
        let albums = try await repository.albums(sortMode: .alphabeticalByName)
        let detail = try await repository.albumDetail(albumID: "album-1")

        XCTAssertEqual(artists.map(\.name), ["Aurora Echo"])
        XCTAssertEqual(albums.map(\.name), ["Analog Dawn"])
        XCTAssertEqual(detail.tracks.first?.title, "First Light")
    }
}
