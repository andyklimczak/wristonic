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

struct AlbumRowView: View {
    let album: AlbumSummary
    let isDownloaded: Bool
    let artworkURL: URL?

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
        .accessibilityElement(children: .combine)
        .accessibilityValue(isDownloaded ? "Downloaded" : "Not downloaded")
    }
}

struct ArtistRowView: View {
    let artist: ArtistSummary
    let hasDownloads: Bool

    var body: some View {
        HStack(spacing: 8) {
            DownloadIndicatorView(isVisible: hasDownloads)
            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name)
                    .lineLimit(1)
                Text("\(artist.albumCount) album\(artist.albumCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(hasDownloads ? "Contains downloads" : "No downloads")
    }
}
