import SwiftUI

struct AlbumDetailView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let albumID: String
    let initialAlbum: AlbumSummary?

    @State private var albumDetail: AlbumDetail?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        List {
            if let albumDetail {
                header(albumDetail: albumDetail)
                actions(albumDetail: albumDetail)
                tracks(albumDetail: albumDetail)
            } else if isLoading {
                ProgressView()
            } else if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            NowPlayingLinkSection()
        }
        .navigationTitle(initialAlbum?.name ?? "Album")
        .task {
            await loadAlbum()
        }
    }

    @ViewBuilder
    private func header(albumDetail: AlbumDetail) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                ArtworkView(
                    url: coverArtURL(for: albumDetail.album.coverArtID),
                    dimension: 72
                )
                HStack(spacing: 6) {
                    DownloadIndicatorView(isVisible: environment.downloadManager.hasLocalContent(albumID: albumDetail.album.id))
                    Text(albumDetail.album.name)
                        .font(.headline)
                }
                Text(albumDetail.album.artistName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(albumDetail.tracks.count) track\(albumDetail.tracks.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func actions(albumDetail: AlbumDetail) -> some View {
        Section("Actions") {
            Button("Play Album") {
                Task {
                    await environment.playbackCoordinator.play(albumDetail: albumDetail, startAt: 0)
                }
            }

            let state = environment.downloadManager.state(for: albumDetail.album.id)
            if state.status == .downloading || state.status == .queued {
                ProgressView(value: state.progress) {
                    Text(state.status == .queued ? "Queued" : "Downloading")
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
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .lineLimit(1)
                            Text(track.duration.map { Int($0.formatted()) } != nil ? durationString(track.duration) : "")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if environment.downloadManager.localFileURL(for: track) != nil {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
    }

    private func loadAlbum() async {
        isLoading = true
        do {
            albumDetail = try await environment.repository.albumDetail(albumID: albumID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func coverArtURL(for coverArtID: String?) -> URL? {
        do {
            return try environment.makeClient().coverArtURL(for: coverArtID)
        } catch {
            return nil
        }
    }

    private func durationString(_ duration: TimeInterval?) -> String {
        guard let duration else { return "" }
        let total = Int(duration)
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
}
