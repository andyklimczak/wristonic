import Foundation

enum AlbumSortMode: String, CaseIterable, Codable, Identifiable {
    case alphabeticalByName
    case random
    case recentlyAdded

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .alphabeticalByName:
            return "Name"
        case .random:
            return "Random"
        case .recentlyAdded:
            return "Recent"
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
}

struct DownloadedTrackRecord: Codable, Hashable {
    var trackID: String
    var relativePath: String
    var bytes: Int64
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
    var lastUpdatedAt: Date?

    static let empty = CachedLibrarySnapshot(
        artists: [],
        albumsBySort: [:],
        albumsByArtist: [:],
        albumDetails: [:],
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
