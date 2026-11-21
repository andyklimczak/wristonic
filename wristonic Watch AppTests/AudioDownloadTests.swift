import XCTest
@testable import wristonic_Watch_App

// Mono 16-bit PCM silence, with a real WAV header for validation and seeking.
func testAudioData(seconds: Int = 1) -> Data {
    var data = Data(base64Encoded: "UklGRqQ+AABXQVZFZm10IBAAAAABAAEAQB8AAIA+AAACABAAZGF0YYA+AAA=")!
    let byteCount = seconds * 16_000
    let riffLength = withUnsafeBytes(of: UInt32(byteCount + 36).littleEndian) { Array($0) }
    let dataLength = withUnsafeBytes(of: UInt32(byteCount).littleEndian) { Array($0) }
    data.replaceSubrange(4..<8, with: riffLength)
    data.replaceSubrange(40..<44, with: dataLength)
    data.append(Data(repeating: 0, count: byteCount))
    return data
}

@MainActor
final class AudioDownloadTests: XCTestCase {
    func testLocalAudioValidationAcceptsAudioAndRejectsErrorBodies() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let validURL = root.appendingPathComponent("valid.wav")
        try testAudioData().write(to: validURL)
        try await LocalAudioFile.validate(validURL)

        let invalidBodies = [
            Data(),
            Data("<html>Sign in</html>".utf8),
            Data(#"{"subsonic-response":{"status":"failed","error":{"message":"Transcoding failed"}}}"#.utf8),
            Data("<subsonic-response status=\"failed\"/>".utf8),
            Data(repeating: 1, count: 1024)
        ]
        for (index, body) in invalidBodies.enumerated() {
            let url = root.appendingPathComponent("invalid-\(index).mp3")
            try body.write(to: url)
            do {
                try await LocalAudioFile.validate(url)
                XCTFail("Accepted invalid audio body \(index)")
            } catch {
                XCTAssertEqual(error.localizedDescription, SubsonicClientError.unsupportedMediaType.localizedDescription)
            }
        }
    }

    func testPlaylistDownloadRetriesInvalidCandidateAndSurvivesReload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = ImmediateDownloadService()
        // HTTP 200 and an audio MIME type must not be sufficient to save a file.
        service.responsesByFormat["aac"] = (Data("<html>Transcoding failed</html>".utf8), "audio/aac")
        let manager = makeManager(root: root, service: service)
        await manager.load()
        let playlist = try await makeClient().playlist(id: "playlist-2")
        manager.enqueue(playlistDetail: playlist)
        try await waitUntilFinished { manager.playlistState(for: playlist.playlist.id).status }

        XCTAssertEqual(manager.playlistState(for: playlist.playlist.id).status, .downloaded)
        for track in playlist.tracks {
            let url = try XCTUnwrap(manager.localFileURL(for: track))
            XCTAssertEqual(url.pathExtension, "wav")
            try await LocalAudioFile.validate(url)
        }
        let formats = service.requests.compactMap { request in
            URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "format" }?.value
        }
        XCTAssertEqual(formats, ["aac", "mp3", "aac", "mp3"])
        XCTAssertTrue(service.temporaryURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        let files = try FileManager.default.subpathsOfDirectory(atPath: root.appendingPathComponent("files").path)
        XCTAssertFalse(files.contains { $0.hasSuffix(".aac") || $0.split(separator: "/").last?.hasPrefix(".") == true })

        // Persist a deterministic snapshot, then verify relative file paths and
        // playlist ownership still resolve without making another request.
        try await JSONFileStore<[DownloadRecord]>(url: root.appendingPathComponent("downloads.json")).save(manager.records)
        try await JSONFileStore<[PlaylistDownloadRecord]>(url: root.appendingPathComponent("playlists.json")).save(manager.playlistRecords)
        let requestCount = service.requests.count
        let reloaded = makeManager(root: root, service: service)
        await reloaded.load()
        XCTAssertTrue(reloaded.isPlaylistFullyDownloaded(playlist))
        XCTAssertEqual(service.requests.count, requestCount)
    }

    func testRedownloadingPlaylistRepairsAnInvalidTrackSharedWithAnAlbum() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = ImmediateDownloadService()
        let manager = makeManager(root: root, service: service)
        await manager.load()
        let client = try makeClient()
        let album = try await client.album(id: "album-1")
        let playlist = try await client.playlist(id: "playlist-2")
        manager.enqueue(albumDetail: album)
        try await waitUntilFinished { manager.state(for: album.album.id).status }
        XCTAssertEqual(manager.state(for: album.album.id).status, .downloaded)
        manager.enqueue(playlistDetail: playlist)
        try await waitUntilFinished { manager.playlistState(for: playlist.playlist.id).status }

        let track = try XCTUnwrap(playlist.tracks.first)
        XCTAssertTrue(album.tracks.contains { $0.id == track.id })
        let savedURL = try XCTUnwrap(manager.localFileURL(for: track))
        try Data("<html>Saved by an older version</html>".utf8).write(to: savedURL, options: .atomic)
        let requestCount = service.requests.count

        manager.enqueue(playlistDetail: playlist)
        try await waitUntilFinished { manager.playlistState(for: playlist.playlist.id).status }

        XCTAssertEqual(manager.playlistState(for: playlist.playlist.id).status, .downloaded)
        let repairedURL = try XCTUnwrap(manager.localFileURL(for: track))
        XCTAssertEqual(repairedURL, savedURL)
        try await LocalAudioFile.validate(repairedURL)
        let streamRequests = service.requests.dropFirst(requestCount).filter { $0.url?.lastPathComponent == "stream.view" }
        XCTAssertEqual(streamRequests.count, 1, "Reuse the other, valid track")
        let repaired = manager.records.flatMap(\.downloadedTracks).first { $0.trackID == track.id }
        XCTAssertEqual(repaired?.bytes, Int64(testAudioData().count))
        XCTAssertEqual(repaired?.ownerKeys, [DownloadManager.ownerKeyForAlbum(album.album.id), DownloadManager.ownerKeyForPlaylist(playlist.playlist.id)])

        manager.deleteDownloadedPlaylist(playlistID: playlist.playlist.id)
        XCTAssertEqual(manager.localFileURL(for: track), repairedURL, "The album still owns the repaired file")
    }

    func testInvalidAlbumDownloadsFailWithoutSavingTracks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = ImmediateDownloadService()
        service.downloadData = Data(#"{"subsonic-response":{"status":"failed"}}"#.utf8)
        let manager = makeManager(root: root, service: service)
        await manager.load()
        let album = try await makeClient().album(id: "album-1")
        manager.enqueue(albumDetail: album)
        let deadline = Date().addingTimeInterval(10)
        while manager.state(for: album.album.id).status != .failed && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(manager.state(for: album.album.id).status, .failed)
        XCTAssertFalse(manager.hasLocalContent(albumID: album.album.id))
        XCTAssertEqual(manager.storagePolicy.savedBytes, 0)
        XCTAssertEqual(service.requests.count, 3)
        XCTAssertTrue(service.temporaryURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    private func makeManager(root: URL, service: DownloadServing) -> DownloadManager {
        DownloadManager(
            settingsStore: makeSettingsStore(name: UUID().uuidString),
            recordsStore: JSONFileStore(url: root.appendingPathComponent("downloads.json")),
            historyStore: JSONFileStore(url: root.appendingPathComponent("history.json")),
            playlistRecordsStore: JSONFileStore(url: root.appendingPathComponent("playlists.json")),
            downloadsDirectory: root.appendingPathComponent("files"),
            downloadService: service,
            clientProvider: { try makeClient() }
        )
    }

    private func waitUntilFinished(_ status: () -> DownloadStatus) async throws {
        try await waitForTestCondition { status() == .downloaded || status() == .failed }
    }
}
