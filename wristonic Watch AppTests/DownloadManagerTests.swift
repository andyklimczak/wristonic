import XCTest
@testable import wristonic_Watch_App

@MainActor
final class DownloadManagerTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try skipOnGitHubActions("Skipped on GitHub Actions because watchOS async download queue tests are flaky in CI.")
    }

    func testDownloadQueueStoresAlbumAndBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let settingsStore = makeSettingsStore(name: UUID().uuidString)
        let downloadService = ImmediateDownloadService()
        let recordsStore = JSONFileStore<[DownloadRecord]>(url: root.appendingPathComponent("downloads.json"))
        let historyStore = JSONFileStore<[String: PlaybackHistory]>(url: root.appendingPathComponent("history.json"))
        let manager = DownloadManager(
            settingsStore: settingsStore,
            recordsStore: recordsStore,
            historyStore: historyStore,
            downloadsDirectory: root.appendingPathComponent("files", isDirectory: true),
            downloadService: downloadService,
            clientProvider: { try makeClient() }
        )
        await manager.load()

        let album = try await makeClient().album(id: "album-1")
        manager.enqueue(albumDetail: album)
        try await wait(for: { manager.state(for: "album-1").status == .downloaded })

        XCTAssertTrue(manager.hasLocalContent(albumID: "album-1"))
        XCTAssertGreaterThan(manager.storagePolicy.savedBytes, 0)
        XCTAssertNotNil(manager.localCoverArtURL(for: "album-1"))
    }

    func testDeleteDownloadedAlbumRemovesFilesAndBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let settingsStore = makeSettingsStore(name: UUID().uuidString)
        let downloadService = ImmediateDownloadService()
        let recordsStore = JSONFileStore<[DownloadRecord]>(url: root.appendingPathComponent("downloads.json"))
        let historyStore = JSONFileStore<[String: PlaybackHistory]>(url: root.appendingPathComponent("history.json"))
        let manager = DownloadManager(
            settingsStore: settingsStore,
            recordsStore: recordsStore,
            historyStore: historyStore,
            downloadsDirectory: root.appendingPathComponent("files", isDirectory: true),
            downloadService: downloadService,
            clientProvider: { try makeClient() }
        )
        await manager.load()

        let album = try await makeClient().album(id: "album-1")
        manager.enqueue(albumDetail: album)
        try await wait(for: { manager.state(for: "album-1").status == .downloaded })

        manager.deleteDownloadedAlbum(albumID: "album-1")

        XCTAssertFalse(manager.hasLocalContent(albumID: "album-1"))
        XCTAssertEqual(manager.storagePolicy.savedBytes, 0)
    }

    func testPinnedAlbumsExceedCapBlocksAdditionalDownloads() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let downloadsDirectory = root.appendingPathComponent("files", isDirectory: true)
        let albumDirectory = downloadsDirectory.appendingPathComponent("album-pinned", isDirectory: true)
        try FileManager.default.createDirectory(at: albumDirectory, withIntermediateDirectories: true)
        let savedFile = albumDirectory.appendingPathComponent("1-track-pinned.mp3")
        try Data(repeating: 0x1, count: 1024).write(to: savedFile)

        let pinnedRecord = DownloadRecord(
            album: AlbumSummary(id: "album-pinned", name: "Pinned", artistID: "artist-1", artistName: "Aurora Echo", coverArtID: nil, songCount: 1, duration: 200, year: 2024, createdAt: nil),
            tracks: [
                Track(id: "track-pinned", albumID: "album-pinned", title: "Pinned Track", artistID: "artist-1", artistName: "Aurora Echo", albumName: "Pinned", duration: 200, trackNumber: 1, discNumber: 1, contentType: "audio/mpeg", suffix: "mp3", path: nil)
            ],
            downloadedTracks: [
                DownloadedTrackRecord(trackID: "track-pinned", relativePath: "album-pinned/1-track-pinned.mp3", bytes: 1024)
            ],
            pinned: true,
            state: DownloadState(status: .downloaded, progress: 1, errorMessage: nil),
            downloadedAt: Date(),
            totalBytes: 1024,
            playCount: 1,
            lastPlayedAt: Date()
        )

        let recordsStore = JSONFileStore<[DownloadRecord]>(url: root.appendingPathComponent("downloads.json"))
        try await recordsStore.save([pinnedRecord])

        let historyStore = JSONFileStore<[String: PlaybackHistory]>(url: root.appendingPathComponent("history.json"))
        let settingsStore = makeSettingsStore(name: UUID().uuidString, capGB: 0)
        let downloadService = ImmediateDownloadService()
        let manager = DownloadManager(
            settingsStore: settingsStore,
            recordsStore: recordsStore,
            historyStore: historyStore,
            downloadsDirectory: downloadsDirectory,
            downloadService: downloadService,
            clientProvider: { try makeClient() }
        )
        await manager.load()

        let album = try await makeClient().album(id: "album-2")
        manager.enqueue(albumDetail: album)
        try await wait(for: { manager.state(for: "album-2").status == .failed })

        XCTAssertTrue(manager.state(for: "album-2").errorMessage?.contains("Pinned albums already exceed the size limit") == true)
    }

    func testInProgressDownloadsRecoverAsQueuedAfterReload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let recordsStore = JSONFileStore<[DownloadRecord]>(url: root.appendingPathComponent("downloads.json"))
        let historyStore = JSONFileStore<[String: PlaybackHistory]>(url: root.appendingPathComponent("history.json"))
        let settingsStore = makeSettingsStore(name: UUID().uuidString)
        let downloadService = ImmediateDownloadService()
        let partialRecord = DownloadRecord(
            album: AlbumSummary(id: "album-2", name: "Blue Circuit", artistID: "artist-1", artistName: "Aurora Echo", coverArtID: nil, songCount: 2, duration: 410, year: 2025, createdAt: nil),
            tracks: [
                Track(id: "track-3", albumID: "album-2", title: "Blue Circuit", artistID: "artist-1", artistName: "Aurora Echo", albumName: "Blue Circuit", duration: 205, trackNumber: 1, discNumber: 1, contentType: "audio/mpeg", suffix: "mp3", path: nil)
            ],
            downloadedTracks: [],
            pinned: false,
            state: DownloadState(status: .downloading, progress: 0.5, errorMessage: nil),
            downloadedAt: nil,
            totalBytes: 0,
            playCount: 0,
            lastPlayedAt: nil
        )
        try await recordsStore.save([partialRecord])

        let manager = DownloadManager(
            settingsStore: settingsStore,
            recordsStore: recordsStore,
            historyStore: historyStore,
            downloadsDirectory: root.appendingPathComponent("files", isDirectory: true),
            downloadService: downloadService,
            clientProvider: { try makeClient() }
        )

        await manager.load()

        XCTAssertEqual(manager.state(for: "album-2").status, .queued)
    }

    private func wait(for condition: @escaping @MainActor () -> Bool, timeout: TimeInterval = 3) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            pumpMainRunLoop()
            await Task.yield()
        }
        XCTFail("Timed out waiting for condition")
    }

    private func pumpMainRunLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }
}
