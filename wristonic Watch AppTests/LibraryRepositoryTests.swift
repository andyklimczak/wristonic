import XCTest
@testable import wristonic_Watch_App

@MainActor
final class LibraryRepositoryTests: XCTestCase {
    func testRecentlyAddedAlbumsForceRefreshUpdatesCachedList() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let settingsStore = makeSettingsStore(name: UUID().uuidString)
        let cacheStore = JSONFileStore<CachedLibrarySnapshot>(url: root.appendingPathComponent("cache.json"))
        let transport = RecordingTransport()
        transport.dataResponses["getAlbumList2"] = Data(DemoMode.albumListPayload.utf8)

        let repository = LibraryRepository(
            cacheStore: cacheStore,
            settingsStore: settingsStore,
            clientProvider: { try makeClient(using: transport) },
            downloadRecordsProvider: { [] }
        )

        let initialAlbums = try await repository.albums(sortMode: .recentlyAdded)
        transport.dataResponses["getAlbumList2"] = Data(Self.albumListPayload(withLeadingAlbumID: "album-4", name: "Fresh Addition").utf8)

        let refreshedAlbums = try await repository.albums(sortMode: .recentlyAdded, forceRefresh: true)

        XCTAssertEqual(initialAlbums.first?.id, "album-1")
        XCTAssertEqual(refreshedAlbums.first?.id, "album-4")
        XCTAssertEqual(transport.requests.filter { $0.url?.lastPathComponent == "getAlbumList2.view" }.count, 2)
    }

    func testAlbumBackgroundRefreshUpdatesCachedList() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let settingsStore = makeSettingsStore(name: UUID().uuidString)
        let cacheStore = JSONFileStore<CachedLibrarySnapshot>(url: root.appendingPathComponent("cache.json"))
        let transport = RecordingTransport()
        transport.dataResponses["getAlbumList2"] = Data(DemoMode.albumListPayload.utf8)

        let repository = LibraryRepository(
            cacheStore: cacheStore,
            settingsStore: settingsStore,
            clientProvider: { try makeClient(using: transport) },
            downloadRecordsProvider: { [] }
        )

        _ = try await repository.albums(sortMode: .recentlyAdded)
        transport.dataResponses["getAlbumList2"] = Data(Self.albumListPayload(withLeadingAlbumID: "album-4", name: "Fresh Addition").utf8)

        try await repository.refreshAlbumsInBackground(sortMode: .recentlyAdded)?.value

        XCTAssertEqual(repository.cachedSnapshot.albumsBySort[AlbumSortMode.recentlyAdded.rawValue]?.first?.id, "album-4")
        XCTAssertEqual(transport.requests.filter { $0.url?.lastPathComponent == "getAlbumList2.view" }.count, 2)
    }

    func testArtistsForceRefreshUpdatesCachedList() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let settingsStore = makeSettingsStore(name: UUID().uuidString)
        let cacheStore = JSONFileStore<CachedLibrarySnapshot>(url: root.appendingPathComponent("cache.json"))
        let transport = RecordingTransport()
        transport.dataResponses["getArtists"] = Data(DemoMode.artistsPayload.utf8)

        let repository = LibraryRepository(
            cacheStore: cacheStore,
            settingsStore: settingsStore,
            clientProvider: { try makeClient(using: transport) },
            downloadRecordsProvider: { [] }
        )

        let initialArtists = try await repository.artists()
        transport.dataResponses["getArtists"] = Data(Self.artistsPayload(withLeadingArtistID: "artist-3", name: "Aardvark Addition").utf8)

        let refreshedArtists = try await repository.artists(forceRefresh: true)

        XCTAssertEqual(initialArtists.first?.id, "artist-1")
        XCTAssertEqual(refreshedArtists.first?.id, "artist-3")
        XCTAssertEqual(transport.requests.filter { $0.url?.lastPathComponent == "getArtists.view" }.count, 2)
    }

    func testArtistAlbumsForceRefreshUpdatesCachedList() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let settingsStore = makeSettingsStore(name: UUID().uuidString)
        let cacheStore = JSONFileStore<CachedLibrarySnapshot>(url: root.appendingPathComponent("cache.json"))
        let transport = RecordingTransport()
        transport.dataResponses["getArtist"] = Data(DemoMode.artistPayloads["artist-1"]!.utf8)

        let repository = LibraryRepository(
            cacheStore: cacheStore,
            settingsStore: settingsStore,
            clientProvider: { try makeClient(using: transport) },
            downloadRecordsProvider: { [] }
        )

        let initialAlbums = try await repository.artistAlbums(artistID: "artist-1")
        transport.dataResponses["getArtist"] = Data(Self.artistPayload(withLeadingAlbumID: "album-4", name: "Aardvark Album").utf8)

        let refreshedAlbums = try await repository.artistAlbums(artistID: "artist-1", forceRefresh: true)

        XCTAssertEqual(initialAlbums.first?.id, "album-1")
        XCTAssertEqual(refreshedAlbums.first?.id, "album-4")
        XCTAssertEqual(transport.requests.filter { $0.url?.lastPathComponent == "getArtist.view" }.count, 2)
    }

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

    func testDownloadedAlbumDetailFallsBackToLocalTracksWhenServerFetchFails() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let settingsStore = makeSettingsStore(name: UUID().uuidString, offlineOnly: false)
        let cacheStore = JSONFileStore<CachedLibrarySnapshot>(url: root.appendingPathComponent("cache.json"))
        let transport = RecordingTransport()
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
            clientProvider: { try makeClient(using: transport) },
            downloadRecordsProvider: { [record] }
        )

        let detail = try await repository.albumDetail(albumID: "album-1", forceRefresh: true)

        XCTAssertEqual(detail.album.name, "Analog Dawn")
        XCTAssertEqual(detail.tracks.map(\.title), ["First Light"])
    }

    func testPlaylistsCacheAfterFetch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let settingsStore = makeSettingsStore(name: UUID().uuidString)
        let cacheStore = JSONFileStore<CachedLibrarySnapshot>(url: root.appendingPathComponent("cache.json"))

        let repository = LibraryRepository(
            cacheStore: cacheStore,
            settingsStore: settingsStore,
            clientProvider: { try makeClient() },
            downloadRecordsProvider: { [] }
        )

        let playlists = try await repository.playlists()
        let detail = try await repository.playlistDetail(playlistID: "playlist-1")

        XCTAssertEqual(playlists.map(\.name), ["Run", "Short Mix"])
        XCTAssertEqual(repository.cachedSnapshot.playlists.count, 2)
        XCTAssertEqual(detail.tracks.map(\.id), ["track-1", "track-2", "track-3", "track-4"])
        XCTAssertEqual(repository.cachedSnapshot.playlistDetails["playlist-1"]?.playlist.name, "Run")
    }

    func testOfflineOnlyPlaylistDetailFiltersToDownloadedTracks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let settingsStore = makeSettingsStore(name: UUID().uuidString, offlineOnly: true)
        let cacheStore = JSONFileStore<CachedLibrarySnapshot>(url: root.appendingPathComponent("cache.json"))
        let playlistDetail = try await makeClient().playlist(id: "playlist-1")
        try await cacheStore.save(
            CachedLibrarySnapshot(
                artists: [],
                albumsBySort: [:],
                albumsByArtist: [:],
                albumDetails: [:],
                playlists: [playlistDetail.playlist],
                playlistDetails: [playlistDetail.playlist.id: playlistDetail],
                internetRadioStations: [],
                lastUpdatedAt: Date()
            )
        )

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
        await repository.loadCachedSnapshot()

        let playlists = try await repository.playlists()
        let offlineDetail = try await repository.playlistDetail(playlistID: "playlist-1")

        XCTAssertEqual(playlists.map(\.name), ["Run"])
        XCTAssertEqual(offlineDetail.tracks.map(\.id), ["track-1"])
    }

    private static func albumListPayload(withLeadingAlbumID albumID: String, name: String) -> String {
        """
        {
          "subsonic-response": {
            "status": "ok",
            "version": "1.16.1",
            "albumList2": {
              "album": [
                { "id": "\(albumID)", "name": "\(name)", "artistId": "artist-3", "artist": "Late Arrival", "coverArt": "cover-4", "songCount": 1, "duration": 200, "year": 2026, "created": "2026-04-01T00:00:00Z" },
                { "id": "album-1", "name": "Analog Dawn", "artistId": "artist-1", "artist": "Aurora Echo", "coverArt": "cover-1", "songCount": 2, "duration": 420, "year": 2024, "created": "2026-01-01T00:00:00Z" },
                { "id": "album-2", "name": "Blue Circuit", "artistId": "artist-1", "artist": "Aurora Echo", "coverArt": "cover-2", "songCount": 2, "duration": 410, "year": 2025, "created": "2026-02-01T00:00:00Z" },
                { "id": "album-3", "name": "Night Relay", "artistId": "artist-2", "artist": "North Static", "coverArt": "cover-3", "songCount": 2, "duration": 398, "year": 2023, "created": "2026-03-01T00:00:00Z" }
              ]
            }
          }
        }
        """
    }

    private static func artistsPayload(withLeadingArtistID artistID: String, name: String) -> String {
        """
        {
          "subsonic-response": {
            "status": "ok",
            "version": "1.16.1",
            "artists": {
              "index": [
                {
                  "name": "A",
                  "artist": [
                    { "id": "\(artistID)", "name": "\(name)", "albumCount": 1 },
                    { "id": "artist-1", "name": "Aurora Echo", "albumCount": 2 }
                  ]
                },
                {
                  "name": "N",
                  "artist": [
                    { "id": "artist-2", "name": "North Static", "albumCount": 1 }
                  ]
                }
              ]
            }
          }
        }
        """
    }

    private static func artistPayload(withLeadingAlbumID albumID: String, name: String) -> String {
        """
        {
          "subsonic-response": {
            "status": "ok",
            "version": "1.16.1",
            "artist": {
              "id": "artist-1",
              "name": "Aurora Echo",
              "album": [
                { "id": "\(albumID)", "name": "\(name)", "artistId": "artist-1", "artist": "Aurora Echo", "coverArt": "cover-4", "songCount": 1, "duration": 200, "year": 2026, "created": "2026-04-01T00:00:00Z" },
                { "id": "album-1", "name": "Analog Dawn", "artistId": "artist-1", "artist": "Aurora Echo", "coverArt": "cover-1", "songCount": 2, "duration": 420, "year": 2024, "created": "2026-01-01T00:00:00Z" },
                { "id": "album-2", "name": "Blue Circuit", "artistId": "artist-1", "artist": "Aurora Echo", "coverArt": "cover-2", "songCount": 2, "duration": 410, "year": 2025, "created": "2026-02-01T00:00:00Z" }
              ]
            }
          }
        }
        """
    }
}
