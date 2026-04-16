import SwiftUI

struct AlbumDetailView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let albumID: String
    let initialAlbum: AlbumSummary?

    @State private var albumDetail: AlbumDetail?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showNowPlaying = false

    var body: some View {
        List {
            if let albumDetail {
                primaryPlayAction(albumDetail: albumDetail)
                header(albumDetail: albumDetail)
                actions(albumDetail: albumDetail)
                tracks(albumDetail: albumDetail)
            } else if let initialAlbum {
                header(album: initialAlbum, detailText: summaryDetailText(for: initialAlbum))
                tracksLoadingSection()
            } else if isLoading {
                ProgressView()
            } else if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle(initialAlbum?.name ?? "Album")
        .task(id: albumID) {
            await loadAlbum()
        }
        .navigationDestination(isPresented: $showNowPlaying) {
            NowPlayingView()
        }
    }

    @ViewBuilder
    private func primaryPlayAction(albumDetail: AlbumDetail) -> some View {
        Section {
            Button {
                Task {
                    await environment.playbackCoordinator.play(albumDetail: albumDetail, startAt: 0)
                    showNowPlaying = true
                }
            } label: {
                Label("Play Album", systemImage: "play.fill")
            }
        }
    }

    @ViewBuilder
    private func header(albumDetail: AlbumDetail) -> some View {
        header(album: albumDetail.album, detailText: trackCountText(albumDetail.tracks.count))
    }

    @ViewBuilder
    private func header(album: AlbumSummary, detailText: String?) -> some View {
        Section {
            VStack(alignment: .center, spacing: 10) {
                ArtworkView(
                    url: preferredCoverArtURL(environment: environment, albumID: album.id, coverArtID: album.coverArtID),
                    dimension: 96
                )

                VStack(alignment: .center, spacing: 3) {
                    HStack(spacing: 6) {
                        DownloadIndicatorView(isVisible: environment.downloadManager.hasLocalContent(albumID: album.id))
                        Text(album.name)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)

                    Text(album.artistName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    if let detailText {
                        Text(detailText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func actions(albumDetail: AlbumDetail) -> some View {
        Section("Actions") {
            if isCurrentAlbumPlaying(albumDetail) {
                Button("Open Player") {
                    showNowPlaying = true
                }
            }

            let state = environment.downloadManager.state(for: albumDetail.album.id)
            if state.status == .downloading || state.status == .queued {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: state.progress) {
                        Text(state.status == .queued ? "Queued" : "Downloading")
                    }

                    Text(downloadProgressText(for: albumDetail.album.id))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let speedText = downloadSpeedText(for: albumDetail.album.id) {
                        Text(speedText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Button(environment.downloadManager.hasLocalContent(albumID: albumDetail.album.id) ? "Redownload Album" : "Download Album") {
                    environment.downloadManager.enqueue(albumDetail: albumDetail)
                }
            }

            if environment.downloadManager.hasLocalContent(albumID: albumDetail.album.id) {
                Button("Delete Downloaded Album", role: .destructive) {
                    environment.downloadManager.deleteDownloadedAlbum(albumID: albumDetail.album.id)
                }
            }

            Button(environment.downloadManager.isPinned(albumID: albumDetail.album.id) ? "Unpin Album" : "Pin Album") {
                environment.downloadManager.togglePin(albumID: albumDetail.album.id)
            }
        }
    }

    @ViewBuilder
    private func tracks(albumDetail: AlbumDetail) -> some View {
        Section("Tracks") {
            ForEach(Array(albumDetail.tracks.enumerated()), id: \.element.id) { index, track in
                Button {
                    Task {
                        await environment.playbackCoordinator.play(albumDetail: albumDetail, startAt: index)
                        showNowPlaying = true
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .lineLimit(1)
                            if let duration = track.duration {
                                Text(durationString(duration))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if environment.downloadManager.localFileURL(for: track) != nil {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(environment.playbackCoordinator.isCurrentTrack(track) ? Color.blue : Color.clear)
                            .frame(width: 3)
                            .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tracksLoadingSection() -> some View {
        Section("Tracks") {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            } else {
                ProgressView("Loading tracks")
            }
        }
    }

    private func loadAlbum() async {
        if albumDetail?.album.id == albumID {
            return
        }
        if let cachedDetail = environment.repository.cachedSnapshot.albumDetails[albumID] {
            albumDetail = cachedDetail
            errorMessage = nil
            return
        }
        isLoading = true
        do {
            albumDetail = try await environment.repository.albumDetail(albumID: albumID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func durationString(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    private func summaryDetailText(for album: AlbumSummary) -> String? {
        album.songCount > 0 ? trackCountText(album.songCount) : "Loading tracks"
    }

    private func trackCountText(_ count: Int) -> String {
        "\(count) track\(count == 1 ? "" : "s")"
    }

    private func isCurrentAlbumPlaying(_ albumDetail: AlbumDetail) -> Bool {
        environment.playbackCoordinator.currentAlbum?.id == albumDetail.album.id
    }

    private func downloadProgressText(for albumID: String) -> String {
        guard let record = environment.downloadManager.records.first(where: { $0.album.id == albumID }) else {
            return ""
        }

        let downloadedCount = record.downloadedTracks.count
        let totalCount = record.tracks.count
        guard totalCount > 0 else {
            return record.state.status == .queued ? "Waiting to start" : "Preparing download"
        }

        return "\(downloadedCount)/\(totalCount) downloaded"
    }

    private func downloadSpeedText(for albumID: String) -> String? {
        guard
            let record = environment.downloadManager.records.first(where: { $0.album.id == albumID }),
            let speed = record.state.transferRateBytesPerSecond,
            speed > 0
        else {
            return nil
        }

        return ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file) + "/s"
    }
}
