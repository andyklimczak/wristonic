import XCTest
@testable import wristonic_Watch_App

final class SubsonicClientTests: XCTestCase {
    func testAuthTokenGenerationIsStable() {
        XCTAssertEqual(
            SubsonicClient.authToken(password: "secret", salt: "abcd1234"),
            "56f2ffee872afa6f1cec74ba0fe8baa1"
        )
    }

    func testArtistsDecodesIndexesPayload() async throws {
        let transport = RecordingTransport()
        transport.dataResponses["getArtists"] = Data(DemoMode.artistsPayload.utf8)

        let artists = try await makeClient(using: transport).artists()

        XCTAssertEqual(artists.map(\.name), ["Aurora Echo", "North Static"])
    }

    func testAlbumListRequestUsesExpectedSortMode() async throws {
        let transport = RecordingTransport()
        transport.dataResponses["getAlbumList2"] = Data(DemoMode.albumListPayload.utf8)

        _ = try await makeClient(using: transport).albums(sortMode: .recentlyAdded)

        let components = URLComponents(url: try XCTUnwrap(transport.requests.last?.url), resolvingAgainstBaseURL: false)
        let queryItems = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(queryItems["type"], "newest")
        XCTAssertEqual(queryItems["f"], "json")
    }

    func testStreamCandidatesPreferTranscodedThenOriginal() throws {
        let client = try makeClient()
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

        let candidates = client.streamCandidates(for: track, preferTranscoding: true)

        XCTAssertEqual(candidates.count, 2)
        XCTAssertTrue(candidates[0].request.url?.absoluteString.contains("format=mp3") == true)
        XCTAssertFalse(candidates[1].request.url?.absoluteString.contains("format=mp3") == true)
    }

    func testServerErrorsBubbleMessage() async {
        let transport = RecordingTransport()
        transport.dataResponses["ping"] = Data(#"{"subsonic-response":{"status":"failed","error":{"message":"Bad credentials"}}}"#.utf8)

        do {
            try await makeClient(using: transport).ping()
            XCTFail("Expected ping to fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Bad credentials")
        }
    }

    func testScrobbleRequestUsesSubmissionTrueAndTimestamp() async throws {
        let transport = RecordingTransport()
        transport.dataResponses["scrobble"] = Data(#"{"subsonic-response":{"status":"ok","version":"1.16.1"}}"#.utf8)
        let listenedAt = Date(timeIntervalSince1970: 1_700_000_000)

        try await makeClient(using: transport).scrobble(trackID: "track-1", listenedAt: listenedAt, submission: true)

        let components = URLComponents(url: try XCTUnwrap(transport.requests.last?.url), resolvingAgainstBaseURL: false)
        let queryItems = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(queryItems["id"], "track-1")
        XCTAssertEqual(queryItems["submission"], "true")
        XCTAssertEqual(queryItems["time"], "1700000000000")
    }

    func testNowPlayingRequestUsesSubmissionFalse() async throws {
        let transport = RecordingTransport()
        transport.dataResponses["scrobble"] = Data(#"{"subsonic-response":{"status":"ok","version":"1.16.1"}}"#.utf8)

        try await makeClient(using: transport).reportNowPlaying(trackID: "track-1")

        let components = URLComponents(url: try XCTUnwrap(transport.requests.last?.url), resolvingAgainstBaseURL: false)
        let queryItems = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(queryItems["submission"], "false")
    }
}
