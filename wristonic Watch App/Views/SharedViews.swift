import SwiftUI

struct DownloadIndicatorView: View {
    var isVisible: Bool

    var body: some View {
        Circle()
            .fill(.blue)
            .frame(width: 8, height: 8)
            .opacity(isVisible ? 1 : 0)
            .accessibilityHidden(!isVisible)
    }
}

struct ArtworkView: View {
    let url: URL?
    let dimension: CGFloat
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.gray.opacity(0.2))
                    .overlay(Image(systemName: "music.note.list"))
                    .task(id: url) {
                        guard let url else { return }
                        image = await CoverArtStore.shared.image(for: url)
                    }
            }
        }
        .frame(width: dimension, height: dimension)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct MediaHeaderView: View {
    let artworkURL: URL?
    let artworkSize: CGFloat
    let title: String
    let subtitle: String
    let detail: String?
    var showsDownloadIndicator: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ArtworkView(url: artworkURL, dimension: artworkSize)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    DownloadIndicatorView(isVisible: showsDownloadIndicator)
                    Text(title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct NowPlayingLinkSection: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        if let track = environment.playbackCoordinator.currentTrack {
            Section("Now Playing") {
                NavigationLink {
                    NowPlayingView()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .lineLimit(1)
                        Text(track.artistName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

struct NowPlayingControlsView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        HStack {
            Button {
                environment.playbackCoordinator.seek(by: -15)
            } label: {
                Image(systemName: "gobackward.15")
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                environment.playbackCoordinator.togglePlayback()
            } label: {
                Image(systemName: environment.playbackCoordinator.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                environment.playbackCoordinator.stop()
            } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                environment.playbackCoordinator.seek(by: 15)
            } label: {
                Image(systemName: "goforward.15")
            }
            .buttonStyle(.plain)
        }
        .font(.headline)
    }
}

struct NowPlayingSummarySection: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        if let track = environment.playbackCoordinator.currentTrack {
            Section("Currently Playing") {
                NavigationLink {
                    NowPlayingView()
                } label: {
                    HStack(spacing: 8) {
                        ArtworkView(
                            url: coverArtURL(for: environment.playbackCoordinator.currentAlbum?.coverArtID),
                            dimension: 36
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.albumName)
                                .lineLimit(1)
                            Text(track.title)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: 3)
                            .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func coverArtURL(for coverArtID: String?) -> URL? {
        do {
            return try environment.makeClient().coverArtURL(for: coverArtID)
        } catch {
            return nil
        }
    }
}

struct AlbumRowView: View {
    let album: AlbumSummary
    let isDownloaded: Bool
    let artworkURL: URL?
    var isCurrentPlaying: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            ArtworkView(url: artworkURL, dimension: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    DownloadIndicatorView(isVisible: isDownloaded)
                    Text(album.name)
                        .lineLimit(1)
                }
                Text(album.artistName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .padding(.leading, 8)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isCurrentPlaying ? Color.blue : Color.clear)
                .frame(width: 3)
                .padding(.vertical, 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if isCurrentPlaying {
            parts.append("Currently playing")
        }
        parts.append(isDownloaded ? "Downloaded" : "Not downloaded")
        return parts.joined(separator: ", ")
    }
}

struct ArtistRowView: View {
    let artist: ArtistSummary
    let hasDownloads: Bool
    let artworkURL: URL?

    var body: some View {
        HStack(spacing: 8) {
            ArtworkView(url: artworkURL, dimension: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    DownloadIndicatorView(isVisible: hasDownloads)
                    Text(artist.name)
                        .lineLimit(1)
                }
                Text("\(artist.albumCount) album\(artist.albumCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(hasDownloads ? "Contains downloads" : "No downloads")
    }
}
