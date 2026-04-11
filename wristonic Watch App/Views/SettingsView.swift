import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showClearServerConfirmation = false

    private let bitrateOptions = [96, 128, 192, 256]

    var body: some View {
        List {
            Section("Server") {
                NavigationLink("Server Setup") {
                    ServerSetupView(
                        title: "Server",
                        subtitle: "Update your Subsonic connection.",
                        confirmTitle: "Test Connection",
                        onSuccess: nil
                    )
                }
            }

            Section("Playback") {
                Picker("Bitrate", selection: bitrateBinding) {
                    ForEach(bitrateOptions, id: \.self) { bitrate in
                        Text("\(bitrate) kbps").tag(bitrate)
                    }
                }
                Toggle("Offline Only", isOn: offlineOnlyBinding)
            }

            Section("UI") {
                Toggle("Show Internet Radio", isOn: showInternetRadioBinding)
            }

            Section("Storage") {
                NavigationLink {
                    StorageSettingsView()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Storage")
                        Text("Cap \(environment.settingsStore.settings.storageCapGB) GB")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Saved \(environment.settingsStore.savedBytes.byteCountString)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Clear Server", role: .destructive) {
                    showClearServerConfirmation = true
                }
            }
        }
        .navigationTitle("Settings")
        .onChange(of: environment.settingsStore.settings) { _, _ in
            Task { await environment.settingsStore.persist() }
        }
        .confirmationDialog(
            "Clear saved server, downloads, and cached data from this watch?",
            isPresented: $showClearServerConfirmation
        ) {
            Button("Clear Server", role: .destructive) {
                Task { await environment.clearServerData() }
            }
            Button("Cancel", role: .cancel) {
            }
        }
    }

    private var bitrateBinding: Binding<Int> {
        Binding(
            get: { environment.settingsStore.settings.preferredBitrateKbps },
            set: { environment.settingsStore.settings.preferredBitrateKbps = $0 }
        )
    }

    private var offlineOnlyBinding: Binding<Bool> {
        Binding(
            get: { environment.settingsStore.settings.offlineOnly },
            set: { environment.settingsStore.settings.offlineOnly = $0 }
        )
    }

    private var showInternetRadioBinding: Binding<Bool> {
        Binding(
            get: { environment.settingsStore.settings.showInternetRadio },
            set: { environment.settingsStore.settings.showInternetRadio = $0 }
        )
    }
}
