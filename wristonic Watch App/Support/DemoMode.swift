import Foundation

struct DemoMode {
    static let isEnabled = ProcessInfo.processInfo.environment["WRISTONIC_DEMO_MODE"] == "1"

    static let artistsPayload = """
    {
      "subsonic-response": {
        "status": "ok",
        "version": "1.16.1",
        "artists": {
          "index": [
            {
              "name": "A",
              "artist": [
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

    static let artistPayloads: [String: String] = [
        "artist-1": """
        {
          "subsonic-response": {
            "status": "ok",
            "version": "1.16.1",
            "artist": {
              "id": "artist-1",
              "name": "Aurora Echo",
              "album": [
                { "id": "album-1", "name": "Analog Dawn", "artistId": "artist-1", "artist": "Aurora Echo", "coverArt": "cover-1", "songCount": 2, "duration": 420, "year": 2024, "created": "2026-01-01T00:00:00Z" },
                { "id": "album-2", "name": "Blue Circuit", "artistId": "artist-1", "artist": "Aurora Echo", "coverArt": "cover-2", "songCount": 2, "duration": 410, "year": 2025, "created": "2026-02-01T00:00:00Z" }
              ]
            }
          }
        }
        """,
        "artist-2": """
        {
          "subsonic-response": {
            "status": "ok",
            "version": "1.16.1",
            "artist": {
              "id": "artist-2",
              "name": "North Static",
              "album": [
                { "id": "album-3", "name": "Night Relay", "artistId": "artist-2", "artist": "North Static", "coverArt": "cover-3", "songCount": 2, "duration": 398, "year": 2023, "created": "2026-03-01T00:00:00Z" }
              ]
            }
          }
        }
        """
    ]

    static let albumListPayload = """
    {
      "subsonic-response": {
        "status": "ok",
        "version": "1.16.1",
        "albumList2": {
          "album": [
            { "id": "album-1", "name": "Analog Dawn", "artistId": "artist-1", "artist": "Aurora Echo", "coverArt": "cover-1", "songCount": 2, "duration": 420, "year": 2024, "created": "2026-01-01T00:00:00Z" },
            { "id": "album-2", "name": "Blue Circuit", "artistId": "artist-1", "artist": "Aurora Echo", "coverArt": "cover-2", "songCount": 2, "duration": 410, "year": 2025, "created": "2026-02-01T00:00:00Z" },
            { "id": "album-3", "name": "Night Relay", "artistId": "artist-2", "artist": "North Static", "coverArt": "cover-3", "songCount": 2, "duration": 398, "year": 2023, "created": "2026-03-01T00:00:00Z" }
          ]
        }
      }
    }
    """

    static let albumPayloads: [String: String] = [
        "album-1": """
        {
          "subsonic-response": {
            "status": "ok",
            "version": "1.16.1",
            "album": {
              "id": "album-1",
              "name": "Analog Dawn",
              "artistId": "artist-1",
              "artist": "Aurora Echo",
              "coverArt": "cover-1",
              "songCount": 2,
              "duration": 420,
              "song": [
                { "id": "track-1", "parent": "album-1", "title": "First Light", "artistId": "artist-1", "artist": "Aurora Echo", "album": "Analog Dawn", "track": 1, "discNumber": 1, "duration": 210, "suffix": "mp3", "contentType": "audio/mpeg" },
                { "id": "track-2", "parent": "album-1", "title": "Glass Signal", "artistId": "artist-1", "artist": "Aurora Echo", "album": "Analog Dawn", "track": 2, "discNumber": 1, "duration": 210, "suffix": "mp3", "contentType": "audio/mpeg" }
              ]
            }
          }
        }
        """,
        "album-2": """
        {
          "subsonic-response": {
            "status": "ok",
            "version": "1.16.1",
            "album": {
              "id": "album-2",
              "name": "Blue Circuit",
              "artistId": "artist-1",
              "artist": "Aurora Echo",
              "coverArt": "cover-2",
              "songCount": 2,
              "duration": 410,
              "song": [
                { "id": "track-3", "parent": "album-2", "title": "Blue Circuit", "artistId": "artist-1", "artist": "Aurora Echo", "album": "Blue Circuit", "track": 1, "discNumber": 1, "duration": 205, "suffix": "mp3", "contentType": "audio/mpeg" },
                { "id": "track-4", "parent": "album-2", "title": "Static Bloom", "artistId": "artist-1", "artist": "Aurora Echo", "album": "Blue Circuit", "track": 2, "discNumber": 1, "duration": 205, "suffix": "mp3", "contentType": "audio/mpeg" }
              ]
            }
          }
        }
        """,
        "album-3": """
        {
          "subsonic-response": {
            "status": "ok",
            "version": "1.16.1",
            "album": {
              "id": "album-3",
              "name": "Night Relay",
              "artistId": "artist-2",
              "artist": "North Static",
              "coverArt": "cover-3",
              "songCount": 2,
              "duration": 398,
              "song": [
                { "id": "track-5", "parent": "album-3", "title": "Night Relay", "artistId": "artist-2", "artist": "North Static", "album": "Night Relay", "track": 1, "discNumber": 1, "duration": 199, "suffix": "mp3", "contentType": "audio/mpeg" },
                { "id": "track-6", "parent": "album-3", "title": "Polar Tone", "artistId": "artist-2", "artist": "North Static", "album": "Night Relay", "track": 2, "discNumber": 1, "duration": 199, "suffix": "mp3", "contentType": "audio/mpeg" }
              ]
            }
          }
        }
        """
    ]
}

final class DemoTransport: Transporting {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let data = try responseData(for: request)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!
        return (data, response)
    }

    func download(for request: URLRequest) async throws -> (URL, URLResponse) {
        let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")
        let bytes = Data(repeating: 0x1, count: 2_048)
        try bytes.write(to: temporaryURL)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!
        return (temporaryURL, response)
    }

    private func responseData(for request: URLRequest) throws -> Data {
        guard let url = request.url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return Data()
        }
        let lastPath = url.lastPathComponent
        let endpoint = lastPath.replacingOccurrences(of: ".view", with: "")
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        let string: String
        switch endpoint {
        case "ping":
            string = #"{"subsonic-response":{"status":"ok","version":"1.16.1"}}"#
        case "getArtists":
            string = DemoMode.artistsPayload
        case "getArtist":
            string = DemoMode.artistPayloads[queryItems["id"] ?? ""] ?? DemoMode.artistPayloads["artist-1"]!
        case "getAlbum":
            string = DemoMode.albumPayloads[queryItems["id"] ?? ""] ?? DemoMode.albumPayloads["album-1"]!
        case "getAlbumList2":
            string = DemoMode.albumListPayload
        case "getCoverArt":
            return Data()
        default:
            string = #"{"subsonic-response":{"status":"failed","error":{"message":"Unknown endpoint"}}}"#
        }
        return Data(string.utf8)
    }
}
