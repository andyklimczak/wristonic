import XCTest
@testable import wristonic_Watch_App

@MainActor
final class PlaybackReportingManagerTests: XCTestCase {
    func testQueuedScrobbleRetriesUntilSuccessAcrossReload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let queueStore = JSONFileStore<[PendingPlaybackScrobble]>(url: root.appendingPathComponent("scrobbles.json"))
        let settingsStore = makeSettingsStore(name: UUID().uuidString)
        let transport = RecordingTransport()
        transport.dataResponses["scrobble"] = Data(#"{"subsonic-response":{"status":"failed","error":{"message":"offline"}}}"#.utf8)

        let manager = PlaybackReportingManager(
            queueStore: queueStore,
            settingsStore: settingsStore,
            baseRetryDelay: 60,
            maxRetryDelay: 0.05,
            clientProvider: { try makeClient(using: transport) }
        )
        await manager.load()
        manager.enqueueScrobble(
            for: Track(
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
            ),
            listenedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        try await wait(for: {
            transport.requests.contains { $0.url?.lastPathComponent == "scrobble.view" }
        })

        let persistedAfterFailure = try await queueStore.load(default: [])
        XCTAssertEqual(persistedAfterFailure.count, 1)

        transport.dataResponses["scrobble"] = Data(#"{"subsonic-response":{"status":"ok","version":"1.16.1"}}"#.utf8)

        let reloadedManager = PlaybackReportingManager(
            queueStore: queueStore,
            settingsStore: settingsStore,
            baseRetryDelay: 0.01,
            maxRetryDelay: 0.05,
            clientProvider: { try makeClient(using: transport) }
        )
        await reloadedManager.load()
        reloadedManager.flushIfNeeded(force: true)

        try await waitForEmptyQueue(queueStore)
    }

    func testFailedScrobbleGetsBackoffScheduled() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let queueStore = JSONFileStore<[PendingPlaybackScrobble]>(url: root.appendingPathComponent("scrobbles.json"))
        let settingsStore = makeSettingsStore(name: UUID().uuidString)
        let transport = RecordingTransport()
        transport.dataResponses["scrobble"] = Data(#"{"subsonic-response":{"status":"failed","error":{"message":"offline"}}}"#.utf8)

        let manager = PlaybackReportingManager(
            queueStore: queueStore,
            settingsStore: settingsStore,
            baseRetryDelay: 0.25,
            maxRetryDelay: 1,
            clientProvider: { try makeClient(using: transport) }
        )
        await manager.load()
        manager.enqueueScrobble(
            for: Track(
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
        )

        try await wait(for: {
            transport.requests.contains { $0.url?.lastPathComponent == "scrobble.view" }
        })

        let persisted = try await queueStore.load(default: [])
        XCTAssertEqual(persisted.count, 1)
        XCTAssertEqual(persisted[0].attempts, 1)
        XCTAssertGreaterThan(persisted[0].nextRetryAt.timeIntervalSinceNow, 0.1)
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

    private func waitForEmptyQueue(_ queueStore: JSONFileStore<[PendingPlaybackScrobble]>, timeout: TimeInterval = 3) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let persisted = try await queueStore.load(default: [])
            if persisted.isEmpty {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("Timed out waiting for empty queue")
    }
}
