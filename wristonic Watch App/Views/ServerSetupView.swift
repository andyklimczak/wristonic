import SwiftUI

struct ServerSetupView: View {
    @EnvironmentObject private var environment: AppEnvironment

    let title: String
    let subtitle: String?
    let confirmTitle: String
    var showHeader: Bool = true
    var onSuccess: (() -> Void)?

    @State private var connectionMessage: String?
    @State private var isTestingConnection = false

    var body: some View {
        List {
            if showHeader {
                Section {
                    Text(title)
                        .font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Server") {
                TextField("URL", text: serverURLBinding)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                TextField("Username", text: usernameBinding)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                SecureField("Password", text: passwordBinding)
                Toggle("Allow Insecure", isOn: allowInsecureBinding)
            }

            Section {
                Button(isTestingConnection ? "Connecting..." : confirmTitle) {
                    Task { await saveAndTest() }
                }
                .disabled(isTestingConnection || !environment.settingsStore.canConnect)

                if let connectionMessage {
                    Text(connectionMessage)
                        .font(.caption2)
                        .foregroundStyle(connectionMessage == "Connected" ? .green : .red)
                }
            }
        }
        .navigationTitle(title)
        .onChange(of: environment.settingsStore.settings) { _, _ in
            Task { await environment.settingsStore.persist() }
        }
        .onChange(of: environment.settingsStore.password) { _, _ in
            Task { await environment.settingsStore.persist() }
        }
    }

    private func saveAndTest() async {
        isTestingConnection = true
        defer { isTestingConnection = false }

        do {
            await environment.settingsStore.persist()
            let client = try environment.makeClient()
            try await client.ping()
            connectionMessage = "Connected"
            onSuccess?()
        } catch {
            connectionMessage = error.localizedDescription
        }
    }

    private var serverURLBinding: Binding<String> {
        Binding(
            get: { environment.settingsStore.settings.serverURLString },
            set: { environment.settingsStore.settings.serverURLString = $0 }
        )
    }

    private var usernameBinding: Binding<String> {
        Binding(
            get: { environment.settingsStore.settings.username },
            set: { environment.settingsStore.settings.username = $0 }
        )
    }

    private var passwordBinding: Binding<String> {
        Binding(
            get: { environment.settingsStore.password },
            set: { environment.settingsStore.password = $0 }
        )
    }

    private var allowInsecureBinding: Binding<Bool> {
        Binding(
            get: { environment.settingsStore.settings.allowInsecureConnections },
            set: { environment.settingsStore.settings.allowInsecureConnections = $0 }
        )
    }
}
