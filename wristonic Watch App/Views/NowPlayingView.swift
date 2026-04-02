import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        List {
            if let track = environment.playbackCoordinator.currentTrack {
                Section {
                    Text(track.title)
                        .font(.headline)
                    Text(track.artistName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if environment.playbackCoordinator.duration > 0 {
                        ProgressView(value: environment.playbackCoordinator.elapsed, total: environment.playbackCoordinator.duration)
                    }
                }

                Section("Controls") {
                    Button("Back") {
                        Task { await environment.playbackCoordinator.skipBackward() }
                    }
                    Button(environment.playbackCoordinator.isPlaying ? "Pause" : "Play") {
                        environment.playbackCoordinator.togglePlayback()
                    }
                    Button("Next") {
                        Task { await environment.playbackCoordinator.skipForward() }
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
    }
}
