import AVFoundation
import XCTest
@testable import wristonic_Watch_App

@MainActor
final class PlaybackCacheManagerTests: XCTestCase {
    func testCacheTrackForPlaybackDownloadsCurrentTrackThroughClient() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let recordsStore = JSONFileStore<[PlaybackCacheRecord]>(url: root.appendingPathComponent("playback-cache.json"))
        let cacheDirectory = root.appendingPathComponent("files", isDirectory: true)
        let transport = RecordingTransport()

        let manager = PlaybackCacheManager(
            recordsStore: recordsStore,
            cacheDirectory: cacheDirectory,
            clientProvider: { try makeClient(using: transport) }
        )
        await manager.load()

        let album = try await makeClient().album(id: "album-1")
        let cachedURL = try await manager.cacheTrackForPlayback(album.tracks[0])

        XCTAssertTrue(FileManager.default.fileExists(atPath: cachedURL.path))
        XCTAssertEqual(manager.localFileURL(for: album.tracks[0]), cachedURL)
        XCTAssertEqual(transport.requests.first?.url?.lastPathComponent, "stream.view")
    }

    func testPrimePlaybackQueueCachesUpcomingTracksWithoutCachingCurrentTrack() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let recordsStore = JSONFileStore<[PlaybackCacheRecord]>(url: root.appendingPathComponent("playback-cache.json"))
        let cacheDirectory = root.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let manager = PlaybackCacheManager(
            recordsStore: recordsStore,
            cacheDirectory: cacheDirectory,
            clientProvider: { try makeClient(using: RecordingTransport()) }
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
            clientProvider: { try makeClient(using: RecordingTransport()) }
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

    func testPrimePlaybackQueueKeepsCurrentTrackWhenItIsAlreadyCached() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let recordsStore = JSONFileStore<[PlaybackCacheRecord]>(url: root.appendingPathComponent("playback-cache.json"))
        let cacheDirectory = root.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let manager = PlaybackCacheManager(
            recordsStore: recordsStore,
            cacheDirectory: cacheDirectory,
            clientProvider: { try makeClient(using: RecordingTransport()) }
        )
        await manager.load()

        let album = try await makeClient().album(id: "album-1")
        let currentTrackURL = try await manager.cacheTrackForPlayback(album.tracks[0])
        manager.primePlaybackQueue(album.tracks, currentIndex: 0, excludingTrackIDs: [])

        try await wait(for: {
            manager.localFileURL(for: album.tracks[1]) != nil
        })

        XCTAssertTrue(FileManager.default.fileExists(atPath: currentTrackURL.path))
        XCTAssertEqual(manager.localFileURL(for: album.tracks[0]), currentTrackURL)
        XCTAssertNotNil(manager.localFileURL(for: album.tracks[1]))
    }

    func testCanceledPrefetchDoesNotDeleteAConcurrentForegroundDownload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheDirectory = root.appendingPathComponent("files")
        let gate = TestGate()
        defer { gate.open() }
        var validationURLs: [URL] = []
        let manager = PlaybackCacheManager(
            recordsStore: JSONFileStore(url: root.appendingPathComponent("cache.json")),
            cacheDirectory: cacheDirectory,
            validateAudio: { url in
                validationURLs.append(url)
                if validationURLs.count == 1 { await gate.wait() }
                try await LocalAudioFile.validate(url)
            },
            clientProvider: { try makeClient(using: RecordingTransport()) }
        )
        let album = try await makeClient().album(id: "album-1")
        let upcomingTrack = album.tracks[1]
        manager.primePlaybackQueue(album.tracks, currentIndex: 0, excludingTrackIDs: [])
        try await waitForTestCondition { gate.isWaiting }
        let prefetchedStage = try XCTUnwrap(validationURLs.first)

        let foregroundFile = try await manager.cacheTrackForPlayback(upcomingTrack)
        XCTAssertEqual(validationURLs.count, 2)
        XCTAssertNotEqual(validationURLs.last, prefetchedStage)
        XCTAssertNotEqual(prefetchedStage, foregroundFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: prefetchedStage.path))
        gate.open()
        try await waitForTestCondition { !FileManager.default.fileExists(atPath: prefetchedStage.path) }

        XCTAssertEqual(manager.localFileURL(for: upcomingTrack), foregroundFile)
        try await LocalAudioFile.validate(foregroundFile)
    }

    func testInvalidCacheDownloadIsRejectedAndCleanedUp() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = RecordingTransport()
        transport.downloadData = Data("<html>Sign in</html>".utf8)
        let cacheDirectory = root.appendingPathComponent("files")
        let manager = PlaybackCacheManager(
            recordsStore: JSONFileStore(url: root.appendingPathComponent("cache.json")),
            cacheDirectory: cacheDirectory,
            clientProvider: { try makeClient(using: transport) }
        )
        let album = try await makeClient().album(id: "album-1")
        do {
            _ = try await manager.cacheTrackForPlayback(album.tracks[0])
            XCTFail("Expected invalid audio to be rejected")
        } catch {
            XCTAssertEqual(transport.requests.count, 3)
            XCTAssertTrue(manager.records.isEmpty)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path), [])
        }
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

final class PlaybackTimelineTests: XCTestCase {
    func testCheckpointUsesCurrentPositionAndFallsBackToLastObservation() {
        XCTAssertEqual(PlaybackTimeline.checkpoint(elapsed: 95, playerTime: 100), 100)
        XCTAssertEqual(PlaybackTimeline.checkpoint(elapsed: 95, playerTime: 0), 95)
        XCTAssertEqual(PlaybackTimeline.checkpoint(elapsed: 0.5, playerTime: .nan), 0.5)
    }

    func testPrematureEndUsesMetadataWithRoundingAllowance() {
        XCTAssertTrue(PlaybackTimeline.endedEarly(at: 100, expectedDuration: 210))
        XCTAssertFalse(PlaybackTimeline.endedEarly(at: 209, expectedDuration: 210))
        XCTAssertFalse(PlaybackTimeline.endedEarly(at: 100, expectedDuration: nil))
    }

    func testFailedSeekOrWrongPositionIsNotARecovery() {
        XCTAssertTrue(PlaybackTimeline.reachedCheckpoint(100, actual: 100, seekFinished: true))
        XCTAssertFalse(PlaybackTimeline.reachedCheckpoint(100, actual: 100, seekFinished: false))
        XCTAssertFalse(PlaybackTimeline.reachedCheckpoint(100, actual: 0, seekFinished: true))
    }
}

@MainActor
final class PlaybackCoordinatorTests: XCTestCase {
    func testColdStreamStartsImmediatelyAndFailureResumesFromCachedAudio() async throws {
        try await assertStreamRecovers(after: .AVPlayerItemFailedToPlayToEndTime)
    }

    func testEarlyStreamEndRecoversInsteadOfRepeatingFromZero() async throws {
        try await assertStreamRecovers(after: .AVPlayerItemDidPlayToEndTime)
    }

    private func assertStreamRecovers(after notification: Notification.Name) async throws {
        let transport = RecordingTransport()
        transport.downloadData = testAudioData(seconds: 24)
        let player = RecordingPlayer()
        let harness = try await makePlaybackCoordinatorHarness(
            audioSessionManager: FakeAudioSessionManager(),
            offlineOnly: false,
            fileData: nil,
            trackDuration: 24,
            playbackTransport: transport,
            player: player
        )
        defer { harness.coordinator.stop() }
        harness.coordinator.toggleRepeatAlbum()
        await harness.coordinator.play(albumDetail: harness.albumDetail, startAt: 0)
        let firstItem = try XCTUnwrap(player.currentItem)
        XCTAssertEqual(player.plays.count, 1)
        XCTAssertEqual(player.plays.first?.url.isFileURL, false)
        XCTAssertTrue(transport.requests.isEmpty, "A cold track must start without a complete HTTP download")

        player.streamPosition = 12
        NotificationCenter.default.post(name: notification, object: firstItem)
        try await waitForTestCondition { player.plays.count == 2 || harness.coordinator.lastError != nil }

        XCTAssertEqual(player.plays.count, 2)
        XCTAssertEqual(player.plays.last?.url.isFileURL, true)
        XCTAssertEqual(try XCTUnwrap(player.plays.last?.time), 12, accuracy: 0.25)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(harness.coordinator.currentIndex, 0)
        XCTAssertNil(harness.coordinator.lastError)
    }

    func testPauseDuringRecoveryKeepsTheCheckpointForResume() async throws {
        let transport = RecordingTransport()
        transport.downloadData = testAudioData(seconds: 24)
        let player = RecordingPlayer()
        let gate = TestGate()
        defer { gate.open() }
        var validations = 0
        let harness = try await makePlaybackCoordinatorHarness(
            audioSessionManager: FakeAudioSessionManager(), offlineOnly: false, fileData: nil,
            validateAudio: { url in
                validations += 1
                if validations == 1 { await gate.wait() }
                try await LocalAudioFile.validate(url)
            },
            trackDuration: 24, playbackTransport: transport, player: player
        )
        defer { harness.coordinator.stop() }
        await harness.coordinator.play(albumDetail: harness.albumDetail, startAt: 0)
        let firstItem = try XCTUnwrap(player.currentItem)
        player.streamPosition = 12
        NotificationCenter.default.post(name: .AVPlayerItemFailedToPlayToEndTime, object: firstItem)
        try await waitForTestCondition { gate.isWaiting }

        await harness.coordinator.togglePlayback()
        XCTAssertFalse(harness.coordinator.isBuffering)
        XCTAssertEqual(player.plays.count, 1)
        await harness.coordinator.togglePlayback()
        gate.open()

        XCTAssertEqual(player.plays.count, 2)
        XCTAssertEqual(try XCTUnwrap(player.plays.last?.time), 12, accuracy: 0.25)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testRecoveryDoesNotPlayWhenLocalFileCannotReachTheCheckpoint() async throws {
        let transport = RecordingTransport() // This candidate contains only one second of audio.
        let player = RecordingPlayer()
        let harness = try await makePlaybackCoordinatorHarness(
            audioSessionManager: FakeAudioSessionManager(), offlineOnly: false, fileData: nil,
            trackDuration: 24, playbackTransport: transport, player: player
        )
        defer { harness.coordinator.stop() }
        await harness.coordinator.play(albumDetail: harness.albumDetail, startAt: 0)
        let firstItem = try XCTUnwrap(player.currentItem)

        player.streamPosition = 12
        NotificationCenter.default.post(name: .AVPlayerItemFailedToPlayToEndTime, object: firstItem)
        try await waitForTestCondition { harness.coordinator.lastError != nil }

        XCTAssertEqual(player.plays.count, 1)
        XCTAssertFalse(harness.coordinator.isBuffering)
        XCTAssertEqual(harness.coordinator.elapsed, 12)
        XCTAssertTrue(harness.coordinator.lastError?.contains("previous position") == true)
    }

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

    func testInvalidDownloadOfflineShowsRedownloadErrorWithoutBuffering() async throws {
        let sessionManager = FakeAudioSessionManager()
        let harness = try await makePlaybackCoordinatorHarness(
            audioSessionManager: sessionManager,
            fileData: Data("<html>Not audio</html>".utf8)
        )

        await harness.coordinator.play(albumDetail: harness.albumDetail, startAt: 0)

        XCTAssertEqual(sessionManager.activationCount, 0)
        XCTAssertFalse(harness.coordinator.isPlaying)
        XCTAssertFalse(harness.coordinator.isBuffering)
        XCTAssertTrue(harness.coordinator.lastError?.contains("download it again") == true)
        harness.coordinator.stop()
    }

    func testInvalidDownloadOnlineFallsBackToCachedAudio() async throws {
        let sessionManager = FakeAudioSessionManager()
        // Stop at activation so the test doesn't depend on a real server/audio route.
        sessionManager.activationError = NSError(domain: "Test", code: 1)
        let harness = try await makePlaybackCoordinatorHarness(
            audioSessionManager: sessionManager,
            offlineOnly: false,
            fileData: Data("<html>Not audio</html>".utf8)
        )

        await harness.coordinator.play(albumDetail: harness.albumDetail, startAt: 0)

        XCTAssertEqual(sessionManager.activationCount, 1)
        XCTAssertFalse(harness.coordinator.isBuffering)
        XCTAssertEqual(harness.coordinator.lastError, sessionManager.activationError?.localizedDescription)
        harness.coordinator.stop()
    }

    func testPlayingAgainAfterPausingValidationRestartsTheCandidate() async throws {
        let sessionManager = FakeAudioSessionManager()
        sessionManager.activationError = NSError(domain: "Test", code: 1)
        let gate = TestGate()
        defer { gate.open() }
        var validationCount = 0
        let harness = try await makePlaybackCoordinatorHarness(
            audioSessionManager: sessionManager,
            validateAudio: { url in
                validationCount += 1
                if validationCount == 1 { await gate.wait() }
                try await LocalAudioFile.validate(url)
            }
        )
        defer { harness.coordinator.stop() }
        let initialPlayback = Task { await harness.coordinator.play(albumDetail: harness.albumDetail, startAt: 0) }
        try await waitForTestCondition { gate.isWaiting }
        XCTAssertTrue(harness.coordinator.isBuffering)

        await harness.coordinator.togglePlayback()
        XCTAssertFalse(harness.coordinator.isBuffering)
        await harness.coordinator.togglePlayback()
        gate.open()
        await initialPlayback.value

        XCTAssertEqual(validationCount, 2)
        XCTAssertEqual(sessionManager.activationCount, 1)
        XCTAssertEqual(harness.coordinator.lastError, sessionManager.activationError?.localizedDescription)
    }

    func testEnablingOfflineOnlyDuringValidationBlocksStreamFallback() async throws {
        let sessionManager = FakeAudioSessionManager()
        let gate = TestGate()
        defer { gate.open() }
        let harness = try await makePlaybackCoordinatorHarness(
            audioSessionManager: sessionManager,
            offlineOnly: false,
            validateAudio: { _ in
                await gate.wait()
                throw SubsonicClientError.unsupportedMediaType
            }
        )
        defer { harness.coordinator.stop() }
        let initialPlayback = Task { await harness.coordinator.play(albumDetail: harness.albumDetail, startAt: 0) }
        try await waitForTestCondition { gate.isWaiting }
        harness.settingsStore.settings.offlineOnly = true
        gate.open()
        await initialPlayback.value

        XCTAssertEqual(sessionManager.activationCount, 0)
        XCTAssertFalse(harness.coordinator.isBuffering)
        XCTAssertTrue(harness.coordinator.lastError?.contains("download it again") == true)
    }

    func testPausingDuringAudioSessionActivationPreventsLatePlaybackStart() async throws {
        let sessionManager = DelayedAudioSessionManager()
        let harness = try await makePlaybackCoordinatorHarness(audioSessionManager: sessionManager)

        let playTask = Task {
            await harness.coordinator.play(albumDetail: harness.albumDetail, startAt: 0)
        }
        let deadline = Date().addingTimeInterval(5)
        while sessionManager.activationCount == 0 && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(sessionManager.activationCount, 1)

        await harness.coordinator.togglePlayback()
        sessionManager.finishActivation()
        await playTask.value

        XCTAssertFalse(harness.coordinator.isPlaying)
        XCTAssertFalse(harness.coordinator.isBuffering)
    }
}

private struct PlaybackCoordinatorHarness {
    let coordinator: PlaybackCoordinator
    let albumDetail: AlbumDetail
    let settingsStore: SettingsStore
}

private final class RecordingPlayer: AVPlayer {
    var streamPosition: TimeInterval = 0
    private(set) var plays: [(url: URL, time: TimeInterval)] = []

    // Use AVFoundation's actual seek for the local replacement, but don't
    // require a Bluetooth output route or a real streaming connection.
    override func play() {
        guard let asset = currentItem?.asset as? AVURLAsset else { return }
        plays.append((asset.url, currentTime().seconds))
    }

    override func currentTime() -> CMTime {
        if let asset = currentItem?.asset as? AVURLAsset, !asset.url.isFileURL {
            return CMTime(seconds: streamPosition, preferredTimescale: 600)
        }
        return super.currentTime()
    }
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
private final class DelayedAudioSessionManager: AudioSessionManaging {
    private(set) var activationCount = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func activatePlaybackSession() async throws {
        activationCount += 1
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finishActivation() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private func makePlaybackCoordinatorHarness(
    audioSessionManager: AudioSessionManaging,
    offlineOnly: Bool = true,
    fileData: Data? = testAudioData(),
    validateAudio: LocalAudioFile.Validator? = nil,
    trackDuration: TimeInterval = 210,
    playbackTransport: Transporting? = nil,
    player: AVPlayer? = nil
) async throws -> PlaybackCoordinatorHarness {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let settingsStore = makeSettingsStore(name: UUID().uuidString, offlineOnly: offlineOnly)
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
        duration: trackDuration,
        trackNumber: 1,
        discNumber: 1,
        contentType: "audio/mpeg",
        suffix: "mp3",
        path: nil
    )

    if let fileData {
        let downloadedFile = downloadsDirectory.appendingPathComponent("album-1/1-track-1.wav", isDirectory: false)
        try FileManager.default.createDirectory(at: downloadedFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileData.write(to: downloadedFile)
        try await recordsStore.save([
            DownloadRecord(
                album: album,
                tracks: [track],
                downloadedTracks: [
                    DownloadedTrackRecord(
                        trackID: track.id,
                        relativePath: "album-1/1-track-1.wav",
                        bytes: Int64(fileData.count),
                        ownerKeys: [DownloadManager.ownerKeyForAlbum(album.id)]
                    )
                ],
                pinned: false,
                state: DownloadState(status: .downloaded, progress: 1, errorMessage: nil),
                downloadedAt: Date(),
                totalBytes: Int64(fileData.count),
                playCount: 0,
                lastPlayedAt: nil
            )
        ])
    }

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
        clientProvider: { try makeClient(using: playbackTransport ?? RecordingTransport()) }
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
        validateAudio: validateAudio,
        player: player,
        clientProvider: { try makeClient() }
    )

    await downloadManager.load()
    await playbackCacheManager.load()
    await playbackReportingManager.load()

    return PlaybackCoordinatorHarness(
        coordinator: coordinator,
        albumDetail: AlbumDetail(album: album, tracks: [track]),
        settingsStore: settingsStore
    )
}
