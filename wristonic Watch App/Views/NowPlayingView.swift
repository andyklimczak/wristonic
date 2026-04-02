import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showAlbumDetail = false

    var body: some View {
        List {
            if let track = environment.playbackCoordinator.currentTrack {
                Section {
                    VStack(alignment: .center, spacing: 10) {
                        ArtworkView(
                            url: coverArtURL(for: environment.playbackCoordinator.currentAlbum?.coverArtID),
                            dimension: 96
                        )

                        VStack(alignment: .center, spacing: 3) {
                            Text(track.albumName)
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(track.artistName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(track.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)

                    NowPlayingControlsView()

                    if environment.playbackCoordinator.duration > 0 {
                        HStack {
                            Text(timeString(environment.playbackCoordinator.elapsed))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()

                            ProgressView(
                                value: environment.playbackCoordinator.elapsed,
                                total: environment.playbackCoordinator.duration
                            )
                            .frame(maxWidth: .infinity)

                            Text(timeString(environment.playbackCoordinator.duration))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }

                Section("Controls") {
                    Button("Next Track") {
                        Task { await environment.playbackCoordinator.skipForward() }
                    }
                    Button("Previous Track") {
                        Task { await environment.playbackCoordinator.skipBackward() }
                    }
                    if let album = environment.playbackCoordinator.currentAlbum {
                        Button("Go To Album") {
                            showAlbumDetail = true
                        }
                    }
                }
            } else {
                Text("Nothing is playing.")
                    .foregroundStyle(.secondary)
            }

            if let error = environment.playbackCoordinator.lastError {
                Text(error)
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle("Now Playing")
        .navigationDestination(isPresented: $showAlbumDetail) {
            if let album = environment.playbackCoordinator.currentAlbum {
                AlbumDetailView(albumID: album.id, initialAlbum: album)
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

    private func timeString(_ time: TimeInterval) -> String {
        let totalSeconds = max(Int(time.rounded(.down)), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):" + String(format: "%02d", seconds)
    }
}
