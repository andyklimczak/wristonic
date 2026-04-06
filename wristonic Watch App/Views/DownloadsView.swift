import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showDeleteAllConfirmation = false

    private var queued: [DownloadRecord] {
        environment.downloadManager.records.filter { $0.state.status == .queued }
    }

    private var active: [DownloadRecord] {
        environment.downloadManager.records.filter { $0.state.status == .downloading }
    }

    private var completed: [DownloadRecord] {
        environment.downloadManager.records.filter { $0.hasDownloadedContent }
    }

    private var failed: [DownloadRecord] {
        environment.downloadManager.records.filter { $0.state.status == .failed }
    }

    private var hasAnyDownloadState: Bool {
        !environment.downloadManager.records.isEmpty
    }

    var body: some View {
        List {
            if queued.isEmpty && active.isEmpty && completed.isEmpty && failed.isEmpty {
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
                                environment.downloadManager.deleteDownloadedAlbum(albumID: record.album.id)
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

    private func speedString(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
    }
}
