import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showDeleteAllConfirmation = false
    @State private var showDeleteDownloadConfirmation = false
    @State private var deleteTarget: DownloadDeleteTarget?

    private var queued: [DownloadRecord] {
        environment.downloadManager.records.filter { $0.state.status == .queued }
    }

    private var queuedPlaylists: [PlaylistDownloadRecord] {
        environment.downloadManager.playlistRecords.filter { $0.state.status == .queued }
    }

    private var active: [DownloadRecord] {
        environment.downloadManager.records.filter { $0.state.status == .downloading }
    }

    private var activePlaylists: [PlaylistDownloadRecord] {
        environment.downloadManager.playlistRecords.filter { $0.state.status == .downloading }
    }

    private var completed: [DownloadRecord] {
        environment.downloadManager.records.filter { $0.hasDownloadedContent }
    }

    private var completedPlaylists: [PlaylistDownloadRecord] {
        environment.downloadManager.playlistRecords.filter { $0.hasDownloadedContent }
    }

    private var failed: [DownloadRecord] {
        environment.downloadManager.records.filter { $0.state.status == .failed }
    }

    private var failedPlaylists: [PlaylistDownloadRecord] {
        environment.downloadManager.playlistRecords.filter { $0.state.status == .failed }
    }

    private var hasAnyDownloadState: Bool {
        !environment.downloadManager.records.isEmpty || !environment.downloadManager.playlistRecords.isEmpty
    }

    var body: some View {
        List {
            if queued.isEmpty && queuedPlaylists.isEmpty && active.isEmpty && activePlaylists.isEmpty && completed.isEmpty && completedPlaylists.isEmpty && failed.isEmpty && failedPlaylists.isEmpty {
                Text("No downloads yet.")
                    .foregroundStyle(.secondary)
            }

            if !queued.isEmpty {
                Section("Queued") {
                    ForEach(queued) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.album.name)
                            Text(trackProgressText(for: record))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !queuedPlaylists.isEmpty {
                Section("Queued Playlists") {
                    ForEach(queuedPlaylists) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.playlist.name)
                            Text(playlistTrackProgressText(for: record))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !active.isEmpty {
                Section("Downloading") {
                    ForEach(active) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.album.name)
                            ProgressView(value: record.state.progress)
                            Text(trackProgressText(for: record))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            HStack {
                                if let speed = record.state.transferRateBytesPerSecond, speed > 0 {
                                    Text(speedString(speed))
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !activePlaylists.isEmpty {
                Section("Downloading Playlists") {
                    ForEach(activePlaylists) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.playlist.name)
                            ProgressView(value: record.state.progress)
                            Text(playlistTrackProgressText(for: record))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            HStack {
                                if let speed = record.state.transferRateBytesPerSecond, speed > 0 {
                                    Text(speedString(speed))
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !completed.isEmpty {
                Section("Saved") {
                    ForEach(completed) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(record.album.name)
                                Spacer()
                                if record.pinned {
                                    Image(systemName: "pin.fill")
                                }
                            }
                            Text(record.savedBytes.byteCountString)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(trackProgressText(for: record))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Button("Delete Download", role: .destructive) {
                                deleteTarget = .album(id: record.album.id, name: record.album.name)
                                showDeleteDownloadConfirmation = true
                            }
                        }
                    }
                }
            }

            if !completedPlaylists.isEmpty {
                Section("Saved Playlists") {
                    ForEach(completedPlaylists) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.playlist.name)
                            Text(environment.downloadManager.savedBytes(for: record).byteCountString)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(playlistTrackProgressText(for: record))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Button("Delete Playlist Download", role: .destructive) {
                                deleteTarget = .playlist(id: record.playlist.id, name: record.playlist.name)
                                showDeleteDownloadConfirmation = true
                            }
                        }
                    }
                }
            }

            if !failed.isEmpty {
                Section("Failed") {
                    ForEach(failed) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.album.name)
                            Text(record.state.errorMessage ?? "Download failed")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            if !failedPlaylists.isEmpty {
                Section("Failed Playlists") {
                    ForEach(failedPlaylists) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.playlist.name)
                            Text(record.state.errorMessage ?? "Download failed")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            if hasAnyDownloadState {
                Section {
                    Button("Delete All Downloads", role: .destructive) {
                        showDeleteAllConfirmation = true
                    }
                }
            }
        }
        .navigationTitle("Downloads")
        .confirmationDialog("Delete all downloaded music from this watch?", isPresented: $showDeleteAllConfirmation) {
            Button("Delete All", role: .destructive) {
                environment.downloadManager.deleteAllDownloads()
            }
        }
        .confirmationDialog(deleteConfirmationTitle, isPresented: $showDeleteDownloadConfirmation) {
            switch deleteTarget {
            case .album(let id, _):
                Button("Delete Album Download", role: .destructive) {
                    environment.downloadManager.deleteDownloadedAlbum(albumID: id)
                    deleteTarget = nil
                }
            case .playlist(let id, _):
                Button("Delete Playlist Download", role: .destructive) {
                    environment.downloadManager.deleteDownloadedPlaylist(playlistID: id)
                    deleteTarget = nil
                }
            case nil:
                EmptyView()
            }
        }
    }

    private var deleteConfirmationTitle: String {
        switch deleteTarget {
        case .album(_, let name):
            return "Delete downloaded album \"\(name)\"?"
        case .playlist(_, let name):
            return "Delete downloaded playlist \"\(name)\"?"
        case nil:
            return "Delete download?"
        }
    }

    private func trackProgressText(for record: DownloadRecord) -> String {
        let downloadedCount = record.downloadedTracks.count
        let totalCount = record.tracks.count
        switch record.state.status {
        case .queued:
            return totalCount > 0 ? "\(downloadedCount)/\(totalCount) tracks ready" : "Queued"
        case .downloading:
            return totalCount > 0 ? "\(downloadedCount)/\(totalCount) downloaded" : "Downloading"
        case .downloaded:
            return totalCount > 0 ? "\(downloadedCount)/\(totalCount) tracks saved" : "Saved"
        default:
            return totalCount > 0 ? "\(downloadedCount)/\(totalCount) tracks" : ""
        }
    }

    private func playlistTrackProgressText(for record: PlaylistDownloadRecord) -> String {
        let downloadedCount = record.downloadedTrackIDs.count
        let totalCount = Set(record.tracks.map(\.id)).count
        switch record.state.status {
        case .queued:
            return totalCount > 0 ? "\(downloadedCount)/\(totalCount) tracks ready" : "Queued"
        case .downloading:
            return totalCount > 0 ? "\(downloadedCount)/\(totalCount) downloaded" : "Downloading"
        case .downloaded:
            return totalCount > 0 ? "\(downloadedCount)/\(totalCount) tracks saved" : "Saved"
        default:
            return totalCount > 0 ? "\(downloadedCount)/\(totalCount) tracks" : ""
        }
    }

    private func speedString(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
    }
}

private enum DownloadDeleteTarget: Identifiable {
    case album(id: String, name: String)
    case playlist(id: String, name: String)

    var id: String {
        switch self {
        case .album(let id, _):
            return "album:\(id)"
        case .playlist(let id, _):
            return "playlist:\(id)"
        }
    }
}
