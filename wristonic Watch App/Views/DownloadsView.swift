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
                        Text(record.album.name)
                    }
                }
            }

            if !active.isEmpty {
                Section("Downloading") {
                    ForEach(active) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.album.name)
                            ProgressView(value: record.state.progress)
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
}
