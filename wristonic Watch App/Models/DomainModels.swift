import Foundation

enum AlbumSortMode: String, CaseIterable, Codable, Identifiable {
    case alphabeticalByName
    case random
    case recentlyAdded
    case recentlyPlayed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .alphabeticalByName:
            return "Name"
        case .random:
            return "Random"
        case .recentlyAdded:
            return "Recently Added"
        case .recentlyPlayed:
            return "Recently Played"
        }
    }

    var subsonicType: String {
        switch self {
        case .alphabeticalByName:
            return "alphabeticalByName"
        case .random:
            return "random"
        case .recentlyAdded:
            return "newest"
        case .recentlyPlayed:
            return "recent"
        }
    }
}

enum DownloadStatus: String, Codable {
    case notDownloaded
    case queued
    case downloading
    case downloaded
    case failed
}

struct DownloadState: Codable, Equatable, Hashable {
    var status: DownloadStatus
    var progress: Double
    var errorMessage: String?
    var transferRateBytesPerSecond: Double?

    init(
        status: DownloadStatus,
        progress: Double,
        errorMessage: String?,
        transferRateBytesPerSecond: Double? = nil
    ) {
        self.status = status
        self.progress = progress
        self.errorMessage = errorMessage
        self.transferRateBytesPerSecond = transferRateBytesPerSecond
    }

    static let notDownloaded = DownloadState(status: .notDownloaded, progress: 0, errorMessage: nil)
}

struct ArtistSummary: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var albumCount: Int
}

struct AlbumSummary: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var artistID: String
    var artistName: String
    var coverArtID: String?
    var songCount: Int
    var duration: TimeInterval?
    var year: Int?
    var createdAt: Date?
}

struct Track: Identifiable, Codable, Hashable {
    var id: String
    var albumID: String
    var title: String
    var artistID: String
    var artistName: String
    var albumName: String
    var duration: TimeInterval?
    var trackNumber: Int
    var discNumber: Int
    var contentType: String?
    var suffix: String?
    var path: String?
}

struct AlbumDetail: Identifiable, Codable, Hashable {
    var album: AlbumSummary
    var tracks: [Track]

    var id: String { album.id }
}

struct PlaylistSummary: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var owner: String?
    var songCount: Int
    var duration: TimeInterval?
    var coverArtID: String?
    var createdAt: Date?
    var changedAt: Date?
}

struct PlaylistDetail: Identifiable, Codable, Hashable {
    var playlist: PlaylistSummary
    var tracks: [Track]

    var id: String { playlist.id }
}

struct InternetRadioStation: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var streamURL: URL
    var homePageURL: URL?
    var coverArtID: String?
}

struct PlaybackHistory: Codable, Hashable {
    var trackID: String
    var playCount: Int
    var lastPlayedAt: Date?
}

struct PendingPlaybackScrobble: Identifiable, Codable, Hashable {
    var id: String
    var trackID: String
    var listenedAt: Date
    var createdAt: Date
    var attempts: Int
    var nextRetryAt: Date
}

struct StoragePolicy: Codable, Equatable {
    var capBytes: Int64
    var savedBytes: Int64
    var pinnedBytes: Int64

    var remainingBytes: Int64 {
        max(capBytes - savedBytes, 0)
    }

    var isPinnedOverflow: Bool {
        pinnedBytes > capBytes
    }
}

struct AppSettings: Codable, Equatable {
    var serverURLString: String = ""
    var username: String = ""
    var preferredBitrateKbps: Int = 192
    var allowInsecureConnections: Bool = false
    var storageCapGB: Int = 8
    var offlineOnly: Bool = false
    var showPlaylists: Bool = true
    var showInternetRadio: Bool = true
    var showShuffle: Bool = true
    var albumSortMode: AlbumSortMode = .alphabeticalByName
    var isRepeatingAlbum: Bool = false
    var isShuffleEnabled: Bool = false

    init() {
    }

    private enum CodingKeys: String, CodingKey {
        case serverURLString
        case username
        case preferredBitrateKbps
        case allowInsecureConnections
        case storageCapGB
        case offlineOnly
        case showPlaylists
        case showInternetRadio
        case showShuffle
        case albumSortMode
        case isRepeatingAlbum
        case isShuffleEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serverURLString = try container.decodeIfPresent(String.self, forKey: .serverURLString) ?? ""
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        preferredBitrateKbps = try container.decodeIfPresent(Int.self, forKey: .preferredBitrateKbps) ?? 192
        allowInsecureConnections = try container.decodeIfPresent(Bool.self, forKey: .allowInsecureConnections) ?? false
        storageCapGB = try container.decodeIfPresent(Int.self, forKey: .storageCapGB) ?? 8
        offlineOnly = try container.decodeIfPresent(Bool.self, forKey: .offlineOnly) ?? false
        showPlaylists = try container.decodeIfPresent(Bool.self, forKey: .showPlaylists) ?? true
        showInternetRadio = try container.decodeIfPresent(Bool.self, forKey: .showInternetRadio) ?? true
        showShuffle = try container.decodeIfPresent(Bool.self, forKey: .showShuffle) ?? true
        albumSortMode = try container.decodeIfPresent(AlbumSortMode.self, forKey: .albumSortMode) ?? .alphabeticalByName
        isRepeatingAlbum = try container.decodeIfPresent(Bool.self, forKey: .isRepeatingAlbum) ?? false
        isShuffleEnabled = try container.decodeIfPresent(Bool.self, forKey: .isShuffleEnabled) ?? false
    }
}

struct DownloadedTrackRecord: Codable, Hashable {
    var trackID: String
    var relativePath: String
    var bytes: Int64
    var ownerKeys: Set<String> = []

    private enum CodingKeys: String, CodingKey {
        case trackID
        case relativePath
        case bytes
        case ownerKeys
    }

    init(trackID: String, relativePath: String, bytes: Int64, ownerKeys: Set<String> = []) {
        self.trackID = trackID
        self.relativePath = relativePath
        self.bytes = bytes
        self.ownerKeys = ownerKeys
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trackID = try container.decode(String.self, forKey: .trackID)
        relativePath = try container.decode(String.self, forKey: .relativePath)
        bytes = try container.decode(Int64.self, forKey: .bytes)
        ownerKeys = try container.decodeIfPresent(Set<String>.self, forKey: .ownerKeys) ?? []
    }
}

struct PlaylistDownloadRecord: Identifiable, Codable, Hashable {
    var playlist: PlaylistSummary
    var tracks: [Track]
    var downloadedTrackIDs: [String]
    var localCoverArtRelativePath: String?
    var coverArtBytes: Int64
    var state: DownloadState
    var downloadedAt: Date?
    var totalBytes: Int64

    var id: String { playlist.id }

    var hasDownloadedContent: Bool {
        !downloadedTrackIDs.isEmpty
    }

    init(
        playlist: PlaylistSummary,
        tracks: [Track],
        downloadedTrackIDs: [String],
        localCoverArtRelativePath: String? = nil,
        coverArtBytes: Int64 = 0,
        state: DownloadState,
        downloadedAt: Date?,
        totalBytes: Int64
    ) {
        self.playlist = playlist
        self.tracks = tracks
        self.downloadedTrackIDs = downloadedTrackIDs
        self.localCoverArtRelativePath = localCoverArtRelativePath
        self.coverArtBytes = coverArtBytes
        self.state = state
        self.downloadedAt = downloadedAt
        self.totalBytes = totalBytes
    }

    private enum CodingKeys: String, CodingKey {
        case playlist
        case tracks
        case downloadedTrackIDs
        case localCoverArtRelativePath
        case coverArtBytes
        case state
        case downloadedAt
        case totalBytes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        playlist = try container.decode(PlaylistSummary.self, forKey: .playlist)
        tracks = try container.decode([Track].self, forKey: .tracks)
        downloadedTrackIDs = try container.decode([String].self, forKey: .downloadedTrackIDs)
        localCoverArtRelativePath = try container.decodeIfPresent(String.self, forKey: .localCoverArtRelativePath)
        coverArtBytes = try container.decodeIfPresent(Int64.self, forKey: .coverArtBytes) ?? 0
        state = try container.decode(DownloadState.self, forKey: .state)
        downloadedAt = try container.decodeIfPresent(Date.self, forKey: .downloadedAt)
        totalBytes = try container.decode(Int64.self, forKey: .totalBytes)
    }
}

struct PlaybackCacheRecord: Codable, Hashable {
    var trackID: String
    var relativePath: String
    var bytes: Int64
    var cachedAt: Date
    var lastAccessedAt: Date
}

struct DownloadRecord: Identifiable, Codable, Hashable {
    var album: AlbumSummary
    var tracks: [Track]
    var downloadedTracks: [DownloadedTrackRecord]
    var localCoverArtRelativePath: String? = nil
    var coverArtBytes: Int64 = 0
    var pinned: Bool
    var state: DownloadState
    var downloadedAt: Date?
    var totalBytes: Int64
    var playCount: Int
    var lastPlayedAt: Date?

    var id: String { album.id }

    var isFullyDownloaded: Bool {
        !tracks.isEmpty && downloadedTracks.count == tracks.count
    }

    var hasDownloadedContent: Bool {
        !downloadedTracks.isEmpty
    }

    var savedBytes: Int64 {
        downloadedTracks.reduce(into: coverArtBytes) { partialResult, track in
            partialResult += track.bytes
        }
    }
}

struct CachedLibrarySnapshot: Codable, Equatable {
    var artists: [ArtistSummary]
    var albumsBySort: [String: [AlbumSummary]]
    var albumsByArtist: [String: [AlbumSummary]]
    var albumDetails: [String: AlbumDetail]
    var playlists: [PlaylistSummary]
    var playlistDetails: [String: PlaylistDetail]
    var internetRadioStations: [InternetRadioStation]
    var lastUpdatedAt: Date?

    init(
        artists: [ArtistSummary],
        albumsBySort: [String: [AlbumSummary]],
        albumsByArtist: [String: [AlbumSummary]],
        albumDetails: [String: AlbumDetail],
        playlists: [PlaylistSummary],
        playlistDetails: [String: PlaylistDetail],
        internetRadioStations: [InternetRadioStation],
        lastUpdatedAt: Date?
    ) {
        self.artists = artists
        self.albumsBySort = albumsBySort
        self.albumsByArtist = albumsByArtist
        self.albumDetails = albumDetails
        self.playlists = playlists
        self.playlistDetails = playlistDetails
        self.internetRadioStations = internetRadioStations
        self.lastUpdatedAt = lastUpdatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case artists
        case albumsBySort
        case albumsByArtist
        case albumDetails
        case playlists
        case playlistDetails
        case internetRadioStations
        case lastUpdatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        artists = try container.decodeIfPresent([ArtistSummary].self, forKey: .artists) ?? []
        albumsBySort = try container.decodeIfPresent([String: [AlbumSummary]].self, forKey: .albumsBySort) ?? [:]
        albumsByArtist = try container.decodeIfPresent([String: [AlbumSummary]].self, forKey: .albumsByArtist) ?? [:]
        albumDetails = try container.decodeIfPresent([String: AlbumDetail].self, forKey: .albumDetails) ?? [:]
        playlists = try container.decodeIfPresent([PlaylistSummary].self, forKey: .playlists) ?? []
        playlistDetails = try container.decodeIfPresent([String: PlaylistDetail].self, forKey: .playlistDetails) ?? [:]
        internetRadioStations = try container.decodeIfPresent([InternetRadioStation].self, forKey: .internetRadioStations) ?? []
        lastUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .lastUpdatedAt)
    }

    static let empty = CachedLibrarySnapshot(
        artists: [],
        albumsBySort: [:],
        albumsByArtist: [:],
        albumDetails: [:],
        playlists: [],
        playlistDetails: [:],
        internetRadioStations: [],
        lastUpdatedAt: nil
    )
}

struct ServerConfiguration: Equatable {
    var baseURL: URL
    var username: String
    var password: String
    var preferredBitrateKbps: Int
    var allowInsecureConnections: Bool
}

extension Int64 {
    var byteCountString: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
