import CryptoKit
import Foundation

enum SubsonicClientError: LocalizedError {
    case invalidResponse
    case server(String)
    case unsupportedMediaType
    case missingPayload(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server returned an invalid response."
        case .server(let message):
            return message
        case .unsupportedMediaType:
            return "The server did not provide a watch-compatible file."
        case .missingPayload(let payload):
            return "The server response was missing \(payload)."
        }
    }
}

struct StreamCandidate {
    var request: URLRequest
    var fileExtension: String
}

final class SubsonicClient {
    private let configuration: ServerConfiguration
    private let transport: Transporting

    init(configuration: ServerConfiguration, transport: Transporting) {
        self.configuration = configuration
        self.transport = transport
    }

    func ping() async throws {
        _ = try await requestDictionary(path: "ping")
    }

    func artists() async throws -> [ArtistSummary] {
        let root = try await requestDictionary(path: "getArtists")
        guard let artistsContainer = root["artists"] as? [String: Any] else {
            throw SubsonicClientError.missingPayload("artists")
        }
        let indexes = Self.dictionaryArray(from: artistsContainer["index"])
        let artists = indexes.flatMap { Self.dictionaryArray(from: $0["artist"]) }
        return artists
            .map(Self.parseArtist)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func albums(for artistID: String) async throws -> [AlbumSummary] {
        let root = try await requestDictionary(path: "getArtist", queryItems: [URLQueryItem(name: "id", value: artistID)])
        guard let artist = root["artist"] as? [String: Any] else {
            throw SubsonicClientError.missingPayload("artist")
        }
        return Self.dictionaryArray(from: artist["album"])
            .map { Self.parseAlbum($0, fallbackArtistID: artistID, fallbackArtistName: artist["name"] as? String ?? "") }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func album(id: String) async throws -> AlbumDetail {
        let root = try await requestDictionary(path: "getAlbum", queryItems: [URLQueryItem(name: "id", value: id)])
        guard let album = root["album"] as? [String: Any] else {
            throw SubsonicClientError.missingPayload("album")
        }

        let summary = Self.parseAlbum(
            album,
            fallbackArtistID: Self.stringValue(from: album["artistId"]) ?? "",
            fallbackArtistName: Self.stringValue(from: album["artist"]) ?? ""
        )
        let tracks = Self.dictionaryArray(from: album["song"]).map {
            Self.parseTrack($0, album: summary)
        }
        return AlbumDetail(album: summary, tracks: tracks.sorted { lhs, rhs in
            if lhs.discNumber == rhs.discNumber {
                return lhs.trackNumber < rhs.trackNumber
            }
            return lhs.discNumber < rhs.discNumber
        })
    }

    func albums(sortMode: AlbumSortMode) async throws -> [AlbumSummary] {
        let root = try await requestDictionary(
            path: "getAlbumList2",
            queryItems: [
                URLQueryItem(name: "type", value: sortMode.subsonicType),
                URLQueryItem(name: "size", value: "200"),
                URLQueryItem(name: "offset", value: "0")
            ]
        )
        guard let albumList = root["albumList2"] as? [String: Any] else {
            throw SubsonicClientError.missingPayload("albumList2")
        }
        return Self.dictionaryArray(from: albumList["album"]).map {
            Self.parseAlbum(
                $0,
                fallbackArtistID: Self.stringValue(from: $0["artistId"]) ?? "",
                fallbackArtistName: Self.stringValue(from: $0["artist"]) ?? ""
            )
        }
    }

    func coverArtURL(for coverArtID: String?) -> URL? {
        guard let coverArtID, !coverArtID.isEmpty else {
            return nil
        }
        return authenticatedURL(path: "getCoverArt", queryItems: [URLQueryItem(name: "id", value: coverArtID)])
    }

    func streamCandidates(for track: Track, preferTranscoding: Bool) -> [StreamCandidate] {
        var candidates: [StreamCandidate] = []
        if preferTranscoding {
            let request = URLRequest(url: authenticatedURL(
                path: "stream",
                queryItems: [
                    URLQueryItem(name: "id", value: track.id),
                    URLQueryItem(name: "maxBitRate", value: String(configuration.preferredBitrateKbps)),
                    URLQueryItem(name: "format", value: "mp3")
                ]
            ))
            candidates.append(StreamCandidate(request: request, fileExtension: "mp3"))
        }

        if let suffix = track.suffix?.lowercased(), Self.supportedSuffixes.contains(suffix) {
            let request = URLRequest(url: authenticatedURL(
                path: "stream",
                queryItems: [URLQueryItem(name: "id", value: track.id)]
            ))
            candidates.append(StreamCandidate(request: request, fileExtension: suffix))
        }
        return candidates
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await transport.data(for: request)
    }

    func download(for request: URLRequest) async throws -> (URL, URLResponse) {
        try await transport.download(for: request)
    }

    private func requestDictionary(path: String, queryItems: [URLQueryItem] = []) async throws -> [String: Any] {
        let url = authenticatedURL(path: path, queryItems: queryItems)
        let (data, _) = try await transport.data(for: URLRequest(url: url))
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let root = json["subsonic-response"] as? [String: Any]
        else {
            throw SubsonicClientError.invalidResponse
        }

        if let status = root["status"] as? String, status != "ok" {
            if
                let error = root["error"] as? [String: Any],
                let message = error["message"] as? String
            {
                throw SubsonicClientError.server(message)
            }
            throw SubsonicClientError.server("The Subsonic request failed.")
        }
        return root
    }

    private func authenticatedURL(path: String, queryItems: [URLQueryItem] = []) -> URL {
        let salt = Self.randomSalt()
        let token = Self.authToken(password: configuration.password, salt: salt)

        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        let trimmedPath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = "\(trimmedPath)/rest/\(path).view"
        components.queryItems = [
            URLQueryItem(name: "u", value: configuration.username),
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "v", value: "1.16.1"),
            URLQueryItem(name: "c", value: "wristonic"),
            URLQueryItem(name: "f", value: "json")
        ] + queryItems
        return components.url!
    }

    private static func parseArtist(_ dictionary: [String: Any]) -> ArtistSummary {
        ArtistSummary(
            id: stringValue(from: dictionary["id"]) ?? UUID().uuidString,
            name: stringValue(from: dictionary["name"]) ?? "Unknown Artist",
            albumCount: intValue(from: dictionary["albumCount"]) ?? 0
        )
    }

    private static func parseAlbum(_ dictionary: [String: Any], fallbackArtistID: String, fallbackArtistName: String) -> AlbumSummary {
        AlbumSummary(
            id: stringValue(from: dictionary["id"]) ?? UUID().uuidString,
            name: stringValue(from: dictionary["name"]) ?? "Unknown Album",
            artistID: stringValue(from: dictionary["artistId"]) ?? fallbackArtistID,
            artistName: stringValue(from: dictionary["artist"]) ?? fallbackArtistName,
            coverArtID: stringValue(from: dictionary["coverArt"]),
            songCount: intValue(from: dictionary["songCount"]) ?? 0,
            duration: doubleValue(from: dictionary["duration"]),
            year: intValue(from: dictionary["year"]),
            createdAt: dateValue(from: dictionary["created"])
        )
    }

    private static func parseTrack(_ dictionary: [String: Any], album: AlbumSummary) -> Track {
        Track(
            id: stringValue(from: dictionary["id"]) ?? UUID().uuidString,
            albumID: stringValue(from: dictionary["parent"]) ?? album.id,
            title: stringValue(from: dictionary["title"]) ?? "Unknown Track",
            artistID: stringValue(from: dictionary["artistId"]) ?? album.artistID,
            artistName: stringValue(from: dictionary["artist"]) ?? album.artistName,
            albumName: stringValue(from: dictionary["album"]) ?? album.name,
            duration: doubleValue(from: dictionary["duration"]),
            trackNumber: intValue(from: dictionary["track"]) ?? 0,
            discNumber: intValue(from: dictionary["discNumber"]) ?? 0,
            contentType: stringValue(from: dictionary["contentType"]),
            suffix: stringValue(from: dictionary["suffix"]),
            path: stringValue(from: dictionary["path"])
        )
    }

    static func dictionaryArray(from rawValue: Any?) -> [[String: Any]] {
        if let value = rawValue as? [[String: Any]] {
            return value
        }
        if let value = rawValue as? [String: Any] {
            return [value]
        }
        return []
    }

    static func stringValue(from value: Any?) -> String? {
        switch value {
        case let value as String:
            return value
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    static func intValue(from value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }

    static func doubleValue(from value: Any?) -> Double? {
        switch value {
        case let value as Double:
            return value
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return Double(value)
        default:
            return nil
        }
    }

    static func dateValue(from value: Any?) -> Date? {
        guard let string = stringValue(from: value) else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)
    }

    static func randomSalt() -> String {
        String(UUID().uuidString.prefix(8))
    }

    static func authToken(password: String, salt: String) -> String {
        Insecure.MD5.hash(data: Data((password + salt).utf8))
            .map { String(format: "%02hhx", $0) }
            .joined()
    }

    static let supportedSuffixes: Set<String> = ["mp3", "m4a", "aac", "wav", "caf", "aif", "aiff"]
}
