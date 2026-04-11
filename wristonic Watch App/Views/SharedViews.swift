import SwiftUI

struct DownloadIndicatorView: View {
    var isVisible: Bool

    var body: some View {
        if isVisible {
            Circle()
                .fill(.blue)
                .frame(width: 8, height: 8)
        }
    }
}

struct ArtworkView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let url: URL?
    let dimension: CGFloat
    @State private var image: Image?
    @State private var loadTask: Task<Void, Never>?

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
            }
        }
        .frame(width: dimension, height: dimension)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onChange(of: url) { _, _ in
            refreshImage()
        }
        .onAppear {
            refreshImage()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private func refreshImage() {
        loadTask?.cancel()
        guard let url else {
            image = nil
            return
        }
        if let cached = CoverArtStore.shared.cachedImage(for: url) {
            image = cached
            return
        }
        image = nil
        scheduleLoad(for: url)
    }

    private func scheduleLoad(for url: URL) {
        loadTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let loaded = await CoverArtStore.shared.image(for: url) { url in
                if url.isFileURL {
                    return try Data(contentsOf: url)
                }
                let client = try environment.makeClient()
                return try await client.data(for: URLRequest(url: url)).0
            }
            guard !Task.isCancelled else { return }
            image = loaded
        }
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
                    if showsDownloadIndicator {
                        DownloadIndicatorView(isVisible: true)
                    }
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

struct NowPlayingControlsView: View {
    @EnvironmentObject private var environment: AppEnvironment

    private var canSeek: Bool {
        environment.playbackCoordinator.currentTrack != nil
    }

    var body: some View {
        HStack {
            Button {
                environment.playbackCoordinator.seek(by: -15)
            } label: {
                Image(systemName: "gobackward.15")
            }
            .buttonStyle(.plain)
            .disabled(!canSeek)

            Spacer()

            Button {
                environment.playbackCoordinator.togglePlayback()
            } label: {
                Image(systemName: environment.playbackCoordinator.isPlaying || environment.playbackCoordinator.isBuffering ? "pause.fill" : "play.fill")
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
            .disabled(!canSeek)
        }
        .font(.headline)
    }
}

struct NowPlayingSummarySection: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        if let station = environment.playbackCoordinator.currentRadioStation {
            Section("Currently Playing") {
                NavigationLink {
                    NowPlayingView()
                } label: {
                    HStack(spacing: 8) {
                        ArtworkView(
                            url: radioCoverArtURL(for: station.coverArtID),
                            dimension: 36
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(station.name)
                                .lineLimit(1)
                            Text(environment.playbackCoordinator.isBuffering ? "Buffering..." : "Internet Radio")
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
        } else if let track = environment.playbackCoordinator.currentTrack {
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
        if let albumID = environment.playbackCoordinator.currentAlbum?.id,
           let localURL = environment.downloadManager.localCoverArtURL(for: albumID) {
            return localURL
        }
        do {
            return try environment.makeClient().coverArtURL(for: coverArtID)
        } catch {
            return nil
        }
    }

    private func radioCoverArtURL(for coverArtID: String?) -> URL? {
        do {
            return try environment.makeClient().coverArtURL(for: coverArtID)
        } catch {
            return nil
        }
    }
}

func preferredCoverArtURL(environment: AppEnvironment, albumID: String, coverArtID: String?) -> URL? {
    if let localURL = environment.downloadManager.localCoverArtURL(for: albumID) {
        return localURL
    }
    do {
        return try environment.makeClient().coverArtURL(for: coverArtID)
    } catch {
        return nil
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
                    if isDownloaded {
                        DownloadIndicatorView(isVisible: true)
                    }
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
                    if hasDownloads {
                        DownloadIndicatorView(isVisible: true)
                    }
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
