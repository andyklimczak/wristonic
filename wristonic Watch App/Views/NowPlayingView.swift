import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showAlbumDetail = false
    @State private var showArtistDetail = false

    var body: some View {
        List {
            if let station = environment.playbackCoordinator.currentRadioStation {
                Section {
                    VStack(alignment: .center, spacing: 10) {
                        ArtworkView(
                            url: radioCoverArtURL(for: station.coverArtID),
                            dimension: 96
                        )

                        VStack(alignment: .center, spacing: 3) {
                            Text(station.name)
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("Internet Radio")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)

                            if environment.playbackCoordinator.isBuffering {
                                Label("Buffering...", systemImage: "dot.radiowaves.left.and.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let homePageURL = station.homePageURL {
                                Text(homePageURL.host() ?? homePageURL.absoluteString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)

                    NowPlayingControlsView()
                }
            } else if let track = environment.playbackCoordinator.currentTrack {
                Section {
                    VStack(alignment: .center, spacing: 10) {
                        ArtworkView(
                            url: nowPlayingCoverArtURL(),
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
                    if environment.playbackCoordinator.currentRadioStation == nil {
                        Button(environment.playbackCoordinator.isRepeatingAlbum ? "Repeat Album On" : "Repeat Album Off") {
                            environment.playbackCoordinator.toggleRepeatAlbum()
                        }
                        Button("Next Track") {
                            Task { await environment.playbackCoordinator.skipForward() }
                        }
                        Button("Previous Track") {
                            Task { await environment.playbackCoordinator.skipBackward() }
                        }
                    }
                    if environment.playbackCoordinator.currentAlbum != nil {
                        Button("Go To Album") {
                            showAlbumDetail = true
                        }
                    }
                    if currentArtist != nil {
                        Button("Go To Artist") {
                            showArtistDetail = true
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
        .navigationDestination(isPresented: $showArtistDetail) {
            if let artist = currentArtist {
                ArtistDetailView(artist: artist)
            }
        }
    }

    private var currentArtist: ArtistSummary? {
        guard let track = environment.playbackCoordinator.currentTrack else {
            return nil
        }
        return ArtistSummary(id: track.artistID, name: track.artistName, albumCount: 0)
    }

    private func nowPlayingCoverArtURL() -> URL? {
        guard let album = environment.playbackCoordinator.currentAlbum else {
            return nil
        }
        return preferredCoverArtURL(environment: environment, albumID: album.id, coverArtID: album.coverArtID)
    }

    private func radioCoverArtURL(for coverArtID: String?) -> URL? {
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
