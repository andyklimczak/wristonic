import SwiftUI

struct StorageSettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        List {
            Section("Storage Cap") {
                Stepper(value: storageCapBinding, in: 1...64) {
                    Text("\(environment.settingsStore.settings.storageCapGB) GB")
                }
            }

            Section("Usage") {
                Text("Saved \(environment.settingsStore.savedBytes.byteCountString)")
                    .foregroundStyle(.secondary)
            }

            Section {
                NavigationLink("Downloads") {
                    DownloadsView()
                }
            }
        }
        .navigationTitle("Storage")
    }

    private var storageCapBinding: Binding<Int> {
        Binding(
            get: { environment.settingsStore.settings.storageCapGB },
            set: { environment.settingsStore.settings.storageCapGB = $0 }
        )
    }
}
