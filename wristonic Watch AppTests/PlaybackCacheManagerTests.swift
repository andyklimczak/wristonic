import XCTest
@testable import wristonic_Watch_App

@MainActor
final class PlaybackCacheManagerTests: XCTestCase {
    func testPrimePlaybackQueueCachesUpcomingTracksWithoutCachingCurrentTrack() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let recordsStore = JSONFileStore<[PlaybackCacheRecord]>(url: root.appendingPathComponent("playback-cache.json"))
        let cacheDirectory = root.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let manager = PlaybackCacheManager(
            recordsStore: recordsStore,
            cacheDirectory: cacheDirectory,
            clientProvider: { try makeClient() }
        )
        await manager.load()

        let album = try await makeClient().album(id: "album-1")
        manager.primePlaybackQueue(album.tracks, currentIndex: 0, excludingTrackIDs: [])

        try await wait(for: {
            manager.localFileURL(for: album.tracks[1]) != nil
        })

        XCTAssertNotNil(manager.localFileURL(for: album.tracks[1]))
        XCTAssertNil(manager.localFileURL(for: album.tracks[0]))
    }

    func testPrimePlaybackQueueEvictsOldCacheOutsidePrefetchWindow() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let recordsStore = JSONFileStore<[PlaybackCacheRecord]>(url: root.appendingPathComponent("playback-cache.json"))
        let cacheDirectory = root.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let manager = PlaybackCacheManager(
            recordsStore: recordsStore,
            cacheDirectory: cacheDirectory,
            clientProvider: { try makeClient() }
        )
        await manager.load()

        let firstAlbum = try await makeClient().album(id: "album-1")
        manager.primePlaybackQueue(firstAlbum.tracks, currentIndex: 0, excludingTrackIDs: [])
        try await wait(for: {
            manager.localFileURL(for: firstAlbum.tracks[1]) != nil
        })

        let secondAlbum = try await makeClient().album(id: "album-3")
        manager.primePlaybackQueue(secondAlbum.tracks, currentIndex: 0, excludingTrackIDs: [])
        try await wait(for: {
            manager.localFileURL(for: secondAlbum.tracks[1]) != nil
        })

        XCTAssertNil(manager.localFileURL(for: firstAlbum.tracks[1]))
        XCTAssertNotNil(manager.localFileURL(for: secondAlbum.tracks[1]))
    }

    private func wait(for condition: @escaping @MainActor () -> Bool, timeout: TimeInterval = 3) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("Timed out waiting for condition")
    }
}

final class PlaybackFailureRecoveryTests: XCTestCase {
    func testFallbackAfterPlaybackStartedResumesAtCurrentPosition() {
        let recovery = PlaybackFailureRecovery.plan(
            currentCandidateIndex: 0,
            candidateCount: 2,
            elapsed: 95,
            playerTime: 100
        )

        XCTAssertEqual(recovery, PlaybackFailureRecovery(candidateIndex: 1, resumeAt: 100))
    }

    func testFallbackBeforePlaybackStartsUsesBeginning() {
        let recovery = PlaybackFailureRecovery.plan(
            currentCandidateIndex: 0,
            candidateCount: 2,
            elapsed: 0.5,
            playerTime: 0.5
        )

        XCTAssertEqual(recovery, PlaybackFailureRecovery(candidateIndex: 1, resumeAt: 0))
    }

    func testFailureWithoutRemainingCandidatesDoesNotRecover() {
        let recovery = PlaybackFailureRecovery.plan(
            currentCandidateIndex: 1,
            candidateCount: 2,
            elapsed: 100,
            playerTime: 100
        )

        XCTAssertNil(recovery)
    }
}

@MainActor
final class PlaybackCoordinatorTests: XCTestCase {
    func testAudioSessionActivationFailureDoesNotMarkTrackAsPlaying() async throws {
        let sessionManager = FakeAudioSessionManager()
        sessionManager.activationError = NSError(
            domain: "AVAudioSessionErrorDomain",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Session activation failed"]
        )
        let harness = try await makePlaybackCoordinatorHarness(audioSessionManager: sessionManager)

        await harness.coordinator.play(albumDetail: harness.albumDetail, startAt: 0)

        XCTAssertEqual(sessionManager.activationCount, 1)
        XCTAssertEqual(harness.coordinator.currentTrack?.id, harness.albumDetail.tracks[0].id)
        XCTAssertFalse(harness.coordinator.isPlaying)
        XCTAssertFalse(harness.coordinator.isBuffering)
        XCTAssertEqual(harness.coordinator.lastError, "Connect Bluetooth audio and try again.")
    }

    func testAudioSessionActivationFailureCanBeRetriedFromCurrentItem() async throws {
        let sessionManager = FakeAudioSessionManager()
        sessionManager.activationError = NSError(
            domain: "AVAudioSessionErrorDomain",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Session activation failed"]
        )
        let harness = try await makePlaybackCoordinatorHarness(audioSessionManager: sessionManager)

        await harness.coordinator.play(albumDetail: harness.albumDetail, startAt: 0)
        sessionManager.activationError = nil
        await harness.coordinator.togglePlayback()

        XCTAssertEqual(sessionManager.activationCount, 2)
        XCTAssertNil(harness.coordinator.lastError)
        XCTAssertEqual(harness.coordinator.currentTrack?.id, harness.albumDetail.tracks[0].id)
    }
}

private struct PlaybackCoordinatorHarness {
    let coordinator: PlaybackCoordinator
    let albumDetail: AlbumDetail
}

private final class FakeAudioSessionManager: AudioSessionManaging {
    var activationError: Error?
    private(set) var activationCount = 0

    func activatePlaybackSession() async throws {
        activationCount += 1
        if let activationError {
            throw activationError
        }
    }
}

@MainActor
private func makePlaybackCoordinatorHarness(
    audioSessionManager: AudioSessionManaging
) async throws -> PlaybackCoordinatorHarness {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let settingsStore = makeSettingsStore(name: UUID().uuidString, offlineOnly: true)
    let recordsStore = JSONFileStore<[DownloadRecord]>(url: root.appendingPathComponent("downloads.json"))
    let playlistRecordsStore = JSONFileStore<[PlaylistDownloadRecord]>(url: root.appendingPathComponent("playlist-downloads.json"))
    let historyStore = JSONFileStore<[String: PlaybackHistory]>(url: root.appendingPathComponent("history.json"))
    let playbackCacheStore = JSONFileStore<[PlaybackCacheRecord]>(url: root.appendingPathComponent("playback-cache.json"))
    let playbackScrobbleStore = JSONFileStore<[PendingPlaybackScrobble]>(url: root.appendingPathComponent("playback-scrobbles.json"))
    let downloadsDirectory = root.appendingPathComponent("downloads", isDirectory: true)
    let playbackCacheDirectory = root.appendingPathComponent("playback-cache-files", isDirectory: true)
    try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: playbackCacheDirectory, withIntermediateDirectories: true)

    let album = AlbumSummary(
        id: "album-1",
        name: "Analog Dawn",
        artistID: "artist-1",
        artistName: "Aurora Echo",
        coverArtID: nil,
        songCount: 1,
        duration: 210,
        year: 2024,
        createdAt: nil
    )
    let track = Track(
        id: "track-1",
        albumID: album.id,
        title: "First Light",
        artistID: album.artistID,
        artistName: album.artistName,
        albumName: album.name,
        duration: 210,
        trackNumber: 1,
        discNumber: 1,
        contentType: "audio/mpeg",
        suffix: "mp3",
        path: nil
    )

    let downloadedFile = downloadsDirectory.appendingPathComponent("album-1/1-track-1.mp3", isDirectory: false)
    try FileManager.default.createDirectory(at: downloadedFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 0x1, count: 1024).write(to: downloadedFile)
    try await recordsStore.save([
        DownloadRecord(
            album: album,
            tracks: [track],
            downloadedTracks: [
                DownloadedTrackRecord(
                    trackID: track.id,
                    relativePath: "album-1/1-track-1.mp3",
                    bytes: 1024,
                    ownerKeys: [DownloadManager.ownerKeyForAlbum(album.id)]
                )
            ],
            pinned: false,
            state: DownloadState(status: .downloaded, progress: 1, errorMessage: nil),
            downloadedAt: Date(),
            totalBytes: 1024,
            playCount: 0,
            lastPlayedAt: nil
        )
    ])

    let downloadManager = DownloadManager(
        settingsStore: settingsStore,
        recordsStore: recordsStore,
        historyStore: historyStore,
        playlistRecordsStore: playlistRecordsStore,
        downloadsDirectory: downloadsDirectory,
        clientProvider: { try makeClient() }
    )
    let playbackCacheManager = PlaybackCacheManager(
        recordsStore: playbackCacheStore,
        cacheDirectory: playbackCacheDirectory,
        clientProvider: { try makeClient() }
    )
    let playbackReportingManager = PlaybackReportingManager(
        queueStore: playbackScrobbleStore,
        settingsStore: settingsStore,
        clientProvider: { try makeClient() }
    )
    let coordinator = PlaybackCoordinator(
        downloadManager: downloadManager,
        playbackCacheManager: playbackCacheManager,
        playbackReportingManager: playbackReportingManager,
        settingsStore: settingsStore,
        audioSessionManager: audioSessionManager,
        clientProvider: { try makeClient() }
    )

    await downloadManager.load()
    await playbackCacheManager.load()
    await playbackReportingManager.load()

    return PlaybackCoordinatorHarness(
        coordinator: coordinator,
        albumDetail: AlbumDetail(album: album, tracks: [track])
    )
}
