import XCTest
@testable import wristonic_Watch_App

@MainActor
final class PlaybackCacheManagerTests: XCTestCase {
    func testPrimePlaybackQueueCachesCurrentAndUpcomingTracks() async throws {
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
            manager.localFileURL(for: album.tracks[0]) != nil && manager.localFileURL(for: album.tracks[1]) != nil
        })

        XCTAssertNotNil(manager.localFileURL(for: album.tracks[0]))
        XCTAssertNotNil(manager.localFileURL(for: album.tracks[1]))
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
            manager.localFileURL(for: firstAlbum.tracks[0]) != nil
        })

        let secondAlbum = try await makeClient().album(id: "album-3")
        manager.primePlaybackQueue(secondAlbum.tracks, currentIndex: 0, excludingTrackIDs: [])
        try await wait(for: {
            manager.localFileURL(for: secondAlbum.tracks[0]) != nil
        })

        XCTAssertNil(manager.localFileURL(for: firstAlbum.tracks[0]))
        XCTAssertNotNil(manager.localFileURL(for: secondAlbum.tracks[0]))
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
