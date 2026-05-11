import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var playlists: [PlaylistSummary] = []
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        List {
            if isLoading && playlists.isEmpty {
                ProgressView()
            } else if let errorMessage, playlists.isEmpty {
                Text(errorMessage)
                    .foregroundStyle(.red)
            } else if playlists.isEmpty {
                Text(environment.settingsStore.settings.offlineOnly ? "No cached playlists." : "No playlists found.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(playlists) { playlist in
                    NavigationLink {
                        PlaylistDetailView(playlistID: playlist.id, initialPlaylist: playlist)
                    } label: {
                        PlaylistRowView(
                            playlist: playlist,
                            isDownloaded: environment.downloadManager.hasLocalContent(playlistID: playlist.id),
                            artworkURL: playlistCoverArtURL(for: playlist),
                            isCurrentPlaying: environment.playbackCoordinator.currentPlaylist?.id == playlist.id
                        )
                    }
                }
            }
        }
        .navigationTitle("Playlists")
        .task {
            await loadPlaylists()
        }
        .refreshable {
            await loadPlaylists(forceRefresh: true)
        }
        .onChange(of: environment.settingsStore.settings.offlineOnly) { _, _ in
            Task { await loadPlaylists() }
        }
    }

    private func loadPlaylists(forceRefresh: Bool = false) async {
        if playlists.isEmpty {
            playlists = environment.repository.cachedSnapshot.playlists
        }
        isLoading = true
        do {
            playlists = try await environment.repository.playlists(forceRefresh: forceRefresh)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func playlistCoverArtURL(for playlist: PlaylistSummary) -> URL? {
        if let localURL = environment.downloadManager.localPlaylistCoverArtURL(for: playlist.id) {
            return localURL
        }
        do {
            return try environment.makeClient().coverArtURL(for: playlist.coverArtID)
        } catch {
            return nil
        }
    }
}

struct PlaylistDetailView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let playlistID: String
    let initialPlaylist: PlaylistSummary?

    @State private var playlistDetail: PlaylistDetail?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showNowPlaying = false
    @State private var showDeleteDownloadConfirmation = false

    var body: some View {
        List {
            if let playlistDetail {
                primaryPlayAction(playlistDetail: playlistDetail)
                header(playlistDetail: playlistDetail)
                actions(playlistDetail: playlistDetail)
                tracks(playlistDetail: playlistDetail)
            } else if let initialPlaylist {
                header(playlist: initialPlaylist, detailText: summaryDetailText(for: initialPlaylist))
                tracksLoadingSection()
            } else if isLoading {
                ProgressView()
            } else if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle(initialPlaylist?.name ?? "Playlist")
        .task(id: playlistID) {
            await loadPlaylist()
        }
        .navigationDestination(isPresented: $showNowPlaying) {
            NowPlayingView()
        }
        .confirmationDialog("Delete downloaded playlist from this watch?", isPresented: $showDeleteDownloadConfirmation) {
            Button("Delete Playlist Download", role: .destructive) {
                guard let playlistDetail else { return }
                environment.downloadManager.deleteDownloadedPlaylist(playlistID: playlistDetail.playlist.id)
            }
        }
    }

    @ViewBuilder
    private func primaryPlayAction(playlistDetail: PlaylistDetail) -> some View {
        Section {
            Button {
                Task {
                    await environment.playbackCoordinator.play(playlistDetail: playlistDetail, startAt: 0)
                    showNowPlaying = true
                }
            } label: {
                Label("Play Playlist", systemImage: "play.fill")
            }
            .disabled(playlistDetail.tracks.isEmpty)
        }
    }

    @ViewBuilder
    private func header(playlistDetail: PlaylistDetail) -> some View {
        header(playlist: playlistDetail.playlist, detailText: trackCountText(playlistDetail.tracks.count))
    }

    @ViewBuilder
    private func header(playlist: PlaylistSummary, detailText: String?) -> some View {
        Section {
            VStack(alignment: .center, spacing: 10) {
                ArtworkView(
                    url: playlistCoverArtURL(for: playlist),
                    dimension: 96
                )

                VStack(alignment: .center, spacing: 3) {
                    HStack(spacing: 6) {
                        DownloadIndicatorView(isVisible: environment.downloadManager.hasLocalContent(playlistID: playlist.id))
                        Text(playlist.name)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)

                    if let owner = playlist.owner, !owner.isEmpty {
                        Text(owner)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

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
    private func actions(playlistDetail: PlaylistDetail) -> some View {
        Section("Actions") {
            if environment.playbackCoordinator.currentPlaylist?.id == playlistDetail.playlist.id {
                Button("Open Player") {
                    showNowPlaying = true
                }
            }

            let state = environment.downloadManager.playlistState(for: playlistDetail.playlist.id)
            if state.status == .downloading || state.status == .queued {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: state.progress) {
                        Text(state.status == .queued ? "Queued" : "Downloading")
                    }

                    Text(downloadProgressText(for: playlistDetail))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let speedText = downloadSpeedText(for: playlistDetail.playlist.id) {
                        Text(speedText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if !environment.settingsStore.settings.offlineOnly {
                Button(environment.downloadManager.hasLocalContent(playlistID: playlistDetail.playlist.id) ? "Redownload Playlist" : "Download Playlist") {
                    environment.downloadManager.enqueue(playlistDetail: playlistDetail)
                }
            }

            if environment.downloadManager.hasLocalContent(playlistID: playlistDetail.playlist.id) {
                Button("Delete Downloaded Playlist", role: .destructive) {
                    showDeleteDownloadConfirmation = true
                }
            }
        }
    }

    @ViewBuilder
    private func tracks(playlistDetail: PlaylistDetail) -> some View {
        Section("Tracks") {
            ForEach(Array(playlistDetail.tracks.enumerated()), id: \.element.id) { index, track in
                Button {
                    Task {
                        await environment.playbackCoordinator.play(playlistDetail: playlistDetail, startAt: index)
                        showNowPlaying = true
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .lineLimit(1)
                            Text(track.albumName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
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
                .disabled(environment.settingsStore.settings.offlineOnly && environment.downloadManager.localFileURL(for: track) == nil)
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

    private func loadPlaylist() async {
        if playlistDetail?.playlist.id == playlistID {
            return
        }
        if !environment.settingsStore.settings.offlineOnly,
           let cachedDetail = environment.repository.cachedSnapshot.playlistDetails[playlistID] {
            playlistDetail = cachedDetail
            errorMessage = nil
            return
        }
        isLoading = true
        do {
            playlistDetail = try await environment.repository.playlistDetail(playlistID: playlistID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func playlistCoverArtURL(for playlist: PlaylistSummary) -> URL? {
        if let localURL = environment.downloadManager.localPlaylistCoverArtURL(for: playlist.id) {
            return localURL
        }
        do {
            return try environment.makeClient().coverArtURL(for: playlist.coverArtID)
        } catch {
            return nil
        }
    }

    private func summaryDetailText(for playlist: PlaylistSummary) -> String? {
        playlist.songCount > 0 ? trackCountText(playlist.songCount) : "Loading tracks"
    }

    private func trackCountText(_ count: Int) -> String {
        "\(count) track\(count == 1 ? "" : "s")"
    }

    private func downloadProgressText(for playlistDetail: PlaylistDetail) -> String {
        guard let record = environment.downloadManager.playlistRecords.first(where: { $0.playlist.id == playlistDetail.playlist.id }) else {
            return ""
        }

        let downloadedCount = record.downloadedTrackIDs.count
        let totalCount = Set(playlistDetail.tracks.map(\.id)).count
        guard totalCount > 0 else {
            return record.state.status == .queued ? "Waiting to start" : "Preparing download"
        }

        return "\(downloadedCount)/\(totalCount) downloaded"
    }

    private func downloadSpeedText(for playlistID: String) -> String? {
        guard
            let record = environment.downloadManager.playlistRecords.first(where: { $0.playlist.id == playlistID }),
            let speed = record.state.transferRateBytesPerSecond,
            speed > 0
        else {
            return nil
        }

        return ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file) + "/s"
    }
}

private struct PlaylistRowView: View {
    let playlist: PlaylistSummary
    let isDownloaded: Bool
    let artworkURL: URL?
    let isCurrentPlaying: Bool

    var body: some View {
        HStack(spacing: 8) {
            ArtworkView(url: artworkURL, dimension: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    DownloadIndicatorView(isVisible: isDownloaded)
                    Text(playlist.name)
                        .lineLimit(1)
                }

                Text(detailText)
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
                .fill(isCurrentPlaying ? Color.blue : Color.clear)
                .frame(width: 3)
                .padding(.vertical, 2)
        }
    }

    private var detailText: String {
        if playlist.songCount > 0 {
            return "\(playlist.songCount) track\(playlist.songCount == 1 ? "" : "s")"
        }
        if let owner = playlist.owner, !owner.isEmpty {
            return owner
        }
        return "Playlist"
    }
}
