import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showAlbumDetail = false
    @State private var showArtistDetail = false
    @State private var showPlaylistDetail = false

    var body: some View {
        List {
            if let station = environment.playbackCoordinator.currentRadioStation {
                Section {
                    VStack(alignment: .center, spacing: 10) {
                        NowPlayingPlayPauseButton()

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
                }
            } else if let track = environment.playbackCoordinator.currentTrack {
                Section {
                    VStack(alignment: .center, spacing: 10) {
                        NowPlayingPlayPauseButton()

                        ArtworkView(
                            url: nowPlayingCoverArtURL(),
                            dimension: 96
                        )

                        VStack(alignment: .center, spacing: 3) {
                            Text(environment.playbackCoordinator.currentPlaylist?.name ?? track.albumName)
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(track.artistName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(environment.playbackCoordinator.currentPlaylist == nil ? track.title : "\(track.albumName) - \(track.title)")
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
                        Button(repeatButtonTitle) {
                            environment.playbackCoordinator.toggleRepeatAlbum()
                        }
                    }
                    if environment.playbackCoordinator.currentPlaylist != nil {
                        Button("Go To Playlist") {
                            showPlaylistDetail = true
                        }
                    }
                    if currentAlbum != nil {
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
            if let album = currentAlbum {
                AlbumDetailView(albumID: album.id, initialAlbum: album)
            }
        }
        .navigationDestination(isPresented: $showPlaylistDetail) {
            if let playlist = environment.playbackCoordinator.currentPlaylist {
                PlaylistDetailView(playlistID: playlist.id, initialPlaylist: playlist)
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

    private var currentAlbum: AlbumSummary? {
        if let album = environment.playbackCoordinator.currentAlbum {
            return album
        }
        guard let track = environment.playbackCoordinator.currentTrack else {
            return nil
        }
        return AlbumSummary(
            id: track.albumID,
            name: track.albumName,
            artistID: track.artistID,
            artistName: track.artistName,
            coverArtID: nil,
            songCount: 0,
            duration: nil,
            year: nil,
            createdAt: nil
        )
    }

    private var repeatButtonTitle: String {
        let noun = environment.playbackCoordinator.currentPlaylist == nil ? "Album" : "Playlist"
        return environment.playbackCoordinator.isRepeatingAlbum ? "Repeat \(noun) On" : "Repeat \(noun) Off"
    }

    private func nowPlayingCoverArtURL() -> URL? {
        if let album = environment.playbackCoordinator.currentAlbum {
            return preferredCoverArtURL(environment: environment, albumID: album.id, coverArtID: album.coverArtID)
        }
        if let playlist = environment.playbackCoordinator.currentPlaylist {
            if let localURL = environment.downloadManager.localPlaylistCoverArtURL(for: playlist.id) {
                return localURL
            }
            return radioCoverArtURL(for: playlist.coverArtID)
        }
        return nil
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
