import SwiftUI

struct ServerSetupView: View {
    @EnvironmentObject private var environment: AppEnvironment

    let title: String
    let subtitle: String?
    let confirmTitle: String
    var showHeader: Bool = true
    var onSuccess: (() -> Void)?

    @State private var serverAddress = ""
    @State private var username = ""
    @State private var password = ""
    @State private var allowInsecure = false
    @State private var connectionMessage: String?
    @State private var isTestingConnection = false

    var body: some View {
        List {
            if showHeader {
                Section {
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                TextField("Server Address", text: $serverAddress)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)

                Toggle("Allow Insecure", isOn: $allowInsecure)

                if !normalizedServerAddress.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Using")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(normalizedServerAddress)
                            .font(.caption2)
                            .lineLimit(2)
                    }
                }

                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)

                SecureField("Password", text: $password)
            }

            Section {
                Button(isTestingConnection ? "Connecting..." : confirmTitle) {
                    Task { await saveAndTest() }
                }
                .disabled(isTestingConnection || !canConnect)

                if let validationMessage, !canConnect {
                    Text(validationMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let connectionMessage {
                    Text(connectionMessage)
                        .font(.caption2)
                        .foregroundStyle(connectionMessage == "Connected" ? .green : .red)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadDraftFromSettings()
        }
    }

    private var trimmedServerAddress: String {
        serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedServerAddress: String {
        guard !trimmedServerAddress.isEmpty else { return "" }
        if trimmedServerAddress.contains("://") {
            return trimmedServerAddress
        }
        return (allowInsecure ? "http://" : "https://") + trimmedServerAddress
    }

    private var canConnect: Bool {
        guard !trimmedUsername.isEmpty, !password.isEmpty else { return false }
        guard !normalizedServerAddress.isEmpty else { return false }
        return URL(string: normalizedServerAddress) != nil
    }

    private var validationMessage: String? {
        if trimmedServerAddress.isEmpty {
            return "Enter a server address."
        }
        if URL(string: normalizedServerAddress) == nil {
            return "Enter a valid server address."
        }
        if trimmedUsername.isEmpty {
            return "Enter a username."
        }
        if password.isEmpty {
            return "Enter a password."
        }
        return nil
    }

    private func loadDraftFromSettings() {
        let settings = environment.settingsStore.settings
        serverAddress = settings.serverURLString
        username = settings.username
        password = environment.settingsStore.password
        allowInsecure = settings.allowInsecureConnections
    }

    private func saveAndTest() async {
        connectionMessage = nil
        isTestingConnection = true
        defer { isTestingConnection = false }

        var settings = environment.settingsStore.settings
        settings.serverURLString = trimmedServerAddress
        settings.username = trimmedUsername
        settings.allowInsecureConnections = allowInsecure
        environment.settingsStore.settings = settings
        environment.settingsStore.password = password

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
}
