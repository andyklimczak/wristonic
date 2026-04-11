import XCTest
@testable import wristonic_Watch_App

@MainActor
final class AppEnvironmentTests: XCTestCase {
    func testClearServerDataRemovesCachedLibraryDownloadsAndPlaybackState() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let settingsStore = makeSettingsStore(name: UUID().uuidString)
        settingsStore.settings.allowInsecureConnections = true

        let cacheStore = JSONFileStore<CachedLibrarySnapshot>(url: root.appendingPathComponent("cache.json"))
        let downloadsStore = JSONFileStore<[DownloadRecord]>(url: root.appendingPathComponent("downloads.json"))
        let historyStore = JSONFileStore<[String: PlaybackHistory]>(url: root.appendingPathComponent("history.json"))
        let playbackCacheStore = JSONFileStore<[PlaybackCacheRecord]>(url: root.appendingPathComponent("playback-cache.json"))
        let scrobbleStore = JSONFileStore<[PendingPlaybackScrobble]>(url: root.appendingPathComponent("scrobbles.json"))

        let downloadsDirectory = root.appendingPathComponent("downloads", isDirectory: true)
        let playbackCacheDirectory = root.appendingPathComponent("playback-cache-files", isDirectory: true)
        let coverArtCacheDirectory = root.appendingPathComponent("cover-art-cache", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: playbackCacheDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: coverArtCacheDirectory, withIntermediateDirectories: true)
        CoverArtStore.shared.configure(cacheDirectory: coverArtCacheDirectory)

        let album = AlbumSummary(
            id: "album-1",
            name: "Analog Dawn",
            artistID: "artist-1",
            artistName: "Aurora Echo",
            coverArtID: "cover-1",
            songCount: 1,
            duration: 210,
            year: 2024,
            createdAt: nil
        )
        let track = Track(
            id: "track-1",
            albumID: "album-1",
            title: "First Light",
            artistID: "artist-1",
            artistName: "Aurora Echo",
            albumName: "Analog Dawn",
            duration: 210,
            trackNumber: 1,
            discNumber: 1,
            contentType: "audio/mpeg",
            suffix: "mp3",
            path: nil
        )

        try await cacheStore.save(
            CachedLibrarySnapshot(
                artists: [ArtistSummary(id: "artist-1", name: "Aurora Echo", albumCount: 1)],
                albumsBySort: [AlbumSortMode.alphabeticalByName.rawValue: [album]],
                albumsByArtist: ["artist-1": [album]],
                albumDetails: ["album-1": AlbumDetail(album: album, tracks: [track])],
                internetRadioStations: [],
                lastUpdatedAt: Date()
            )
        )

        let downloadedFile = downloadsDirectory.appendingPathComponent("album-1/1-track-1.mp3", isDirectory: false)
        try FileManager.default.createDirectory(at: downloadedFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x1, count: 1024).write(to: downloadedFile)
        try await downloadsStore.save([
            DownloadRecord(
                album: album,
                tracks: [track],
                downloadedTracks: [DownloadedTrackRecord(trackID: "track-1", relativePath: "album-1/1-track-1.mp3", bytes: 1024)],
                localCoverArtRelativePath: nil,
                coverArtBytes: 0,
                pinned: false,
                state: DownloadState(status: .downloaded, progress: 1, errorMessage: nil),
                downloadedAt: Date(),
                totalBytes: 1024,
                playCount: 1,
                lastPlayedAt: Date()
            )
        ])
        try await historyStore.save(["track-1": PlaybackHistory(trackID: "track-1", playCount: 1, lastPlayedAt: Date())])

        let playbackCachedFile = playbackCacheDirectory.appendingPathComponent("album-1-1-track-1.mp3", isDirectory: false)
        try Data(repeating: 0x2, count: 1024).write(to: playbackCachedFile)
        try await playbackCacheStore.save([
            PlaybackCacheRecord(
                trackID: "track-1",
                relativePath: "album-1-1-track-1.mp3",
                bytes: 1024,
                cachedAt: Date(),
                lastAccessedAt: Date()
            )
        ])

        try await scrobbleStore.save([
            PendingPlaybackScrobble(
                id: "pending-1",
                trackID: "track-1",
                listenedAt: Date(),
                createdAt: Date(),
                attempts: 0,
                nextRetryAt: Date()
            )
        ])

        try Data(repeating: 0x3, count: 256).write(to: coverArtCacheDirectory.appendingPathComponent("cover.jpg"))

        var environment: AppEnvironment!
        let downloadManager = DownloadManager(
            settingsStore: settingsStore,
            recordsStore: downloadsStore,
            historyStore: historyStore,
            downloadsDirectory: downloadsDirectory,
            clientProvider: { try environment.makeClient() }
        )
        let playbackCacheManager = PlaybackCacheManager(
            recordsStore: playbackCacheStore,
            cacheDirectory: playbackCacheDirectory,
            clientProvider: { try environment.makeClient() }
        )
        let playbackReportingManager = PlaybackReportingManager(
            queueStore: scrobbleStore,
            settingsStore: settingsStore,
            clientProvider: { try environment.makeClient() }
        )
        let repository = LibraryRepository(
            cacheStore: cacheStore,
            settingsStore: settingsStore,
            clientProvider: { try environment.makeClient() },
            downloadRecordsProvider: { downloadManager.records }
        )
        let playbackCoordinator = PlaybackCoordinator(
            downloadManager: downloadManager,
            playbackCacheManager: playbackCacheManager,
            playbackReportingManager: playbackReportingManager,
            settingsStore: settingsStore,
            clientProvider: { try environment.makeClient() }
        )
        environment = AppEnvironment(
            settingsStore: settingsStore,
            repository: repository,
            downloadManager: downloadManager,
            playbackCacheManager: playbackCacheManager,
            playbackReportingManager: playbackReportingManager,
            playbackCoordinator: playbackCoordinator,
            networkMonitor: NetworkMonitor { },
            transportFactory: { _ in DemoTransport() }
        )

        await repository.loadCachedSnapshot()
        await downloadManager.load()
        await playbackCacheManager.load()
        await playbackReportingManager.load()

        XCTAssertFalse(repository.cachedSnapshot.artists.isEmpty)
        XCTAssertFalse(downloadManager.records.isEmpty)
        XCTAssertFalse(playbackCacheManager.records.isEmpty)

        await environment.clearServerData()

        XCTAssertEqual(repository.cachedSnapshot, .empty)
        XCTAssertTrue(downloadManager.records.isEmpty)
        XCTAssertTrue(playbackCacheManager.records.isEmpty)
        XCTAssertEqual(settingsStore.settings.serverURLString, "")
        XCTAssertEqual(settingsStore.settings.username, "")
        XCTAssertFalse(settingsStore.settings.allowInsecureConnections)
        XCTAssertEqual(settingsStore.password, "")
        XCTAssertNil(playbackCoordinator.currentTrack)
        XCTAssertNil(playbackCoordinator.currentAlbum)

        XCTAssertEqual(try await cacheStore.load(default: .empty), .empty)
        XCTAssertEqual(try await downloadsStore.load(default: []), [])
        XCTAssertEqual(try await historyStore.load(default: [:]), [:])
        XCTAssertEqual(try await playbackCacheStore.load(default: []), [])
        XCTAssertEqual(try await scrobbleStore.load(default: []), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: downloadsDirectory.path), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: playbackCacheDirectory.path), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: coverArtCacheDirectory.path), [])
    }
}
