import SwiftUI

struct InternetRadioView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var stations: [InternetRadioStation] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showNowPlaying = false

    var body: some View {
        List {
            if environment.settingsStore.settings.offlineOnly {
                Text("Internet radio is unavailable in Offline Only mode.")
                    .foregroundStyle(.secondary)
            } else if isLoading && stations.isEmpty {
                ProgressView()
            } else if let errorMessage, stations.isEmpty {
                Text(errorMessage)
                    .foregroundStyle(.red)
            } else if stations.isEmpty {
                Text("No radio stations found.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(stations) { station in
                    Button {
                        environment.playbackCoordinator.play(radioStation: station)
                        showNowPlaying = true
                    } label: {
                        InternetRadioStationRowView(station: station)
                    }
                }
            }
        }
        .navigationTitle("Internet Radio")
        .task {
            await loadStations()
        }
        .refreshable {
            await refreshStations()
        }
        .onChange(of: environment.settingsStore.settings.offlineOnly) { _, _ in
            Task { await loadStations() }
        }
        .navigationDestination(isPresented: $showNowPlaying) {
            NowPlayingView()
        }
    }

    private func loadStations() async {
        guard !environment.settingsStore.settings.offlineOnly else {
            stations = []
            errorMessage = nil
            isLoading = false
            return
        }

        let cachedStations = environment.repository.cachedSnapshot.internetRadioStations
        if !cachedStations.isEmpty {
            stations = cachedStations
            errorMessage = nil
            isLoading = false
            await refreshStations()
            return
        }

        isLoading = true
        do {
            stations = try await environment.repository.internetRadioStations()
            errorMessage = nil
        } catch SubsonicClientError.missingPayload(_) {
            errorMessage = "This server does not expose internet radio stations."
        } catch SubsonicClientError.server(let message) where (
            message.localizedCaseInsensitiveContains("unknown")
            || message.localizedCaseInsensitiveContains("unsupported")
        ) {
            errorMessage = "This server does not expose internet radio stations."
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func refreshStations() async {
        guard !environment.settingsStore.settings.offlineOnly else {
            stations = []
            errorMessage = nil
            isLoading = false
            return
        }

        do {
            stations = try await environment.repository.internetRadioStations(forceRefresh: true)
            errorMessage = nil
        } catch SubsonicClientError.missingPayload(_) {
            errorMessage = stations.isEmpty ? "This server does not expose internet radio stations." : nil
        } catch SubsonicClientError.server(let message) where (
            message.localizedCaseInsensitiveContains("unknown")
            || message.localizedCaseInsensitiveContains("unsupported")
        ) {
            errorMessage = stations.isEmpty ? "This server does not expose internet radio stations." : nil
        } catch {
            errorMessage = stations.isEmpty ? error.localizedDescription : nil
        }
    }
}

private struct InternetRadioStationRowView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let station: InternetRadioStation

    var body: some View {
        HStack(spacing: 8) {
            ArtworkView(url: coverArtURL(for: station.coverArtID), dimension: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(station.name)
                    .lineLimit(1)
                Text(station.homePageURL?.host() ?? "Internet Radio")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func coverArtURL(for coverArtID: String?) -> URL? {
        do {
            return try environment.makeClient().coverArtURL(for: coverArtID)
        } catch {
            return nil
        }
    }
}
