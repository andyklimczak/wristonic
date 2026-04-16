import SwiftUI
import WatchKit

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
    @State private var didSucceed = false

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
                Button {
                    Task { await saveAndTest() }
                } label: {
                    buttonLabel
                }
                .disabled(isTestingConnection || !canConnect)

                if let validationMessage, !canConnect {
                    Text(validationMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let connectionMessage, !didSucceed {
                    Text(connectionMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadDraftFromSettings()
        }
        .onChange(of: serverAddress) { _, _ in
            resetConnectionState()
        }
        .onChange(of: username) { _, _ in
            resetConnectionState()
        }
        .onChange(of: password) { _, _ in
            resetConnectionState()
        }
        .onChange(of: allowInsecure) { _, _ in
            resetConnectionState()
        }
    }

    private var trimmedServerAddress: String {
        serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedServerAddress: String {
        SettingsStore.normalizedServerAddress(from: serverAddress, allowInsecureConnections: allowInsecure)
    }

    private var canConnect: Bool {
        guard !trimmedUsername.isEmpty, !password.isEmpty else { return false }
        return validatedServerURL != nil
    }

    private var validationMessage: String? {
        if trimmedServerAddress.isEmpty {
            return "Enter a server address."
        }
        if validatedServerURL == nil {
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

    private var validatedServerURL: URL? {
        SettingsStore.validatedServerURL(from: serverAddress, allowInsecureConnections: allowInsecure)
    }

    @ViewBuilder
    private var buttonLabel: some View {
        if isTestingConnection {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .fixedSize()
                Text("Testing connection")
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        } else if didSucceed {
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Text(confirmTitle)
        }
    }

    private func saveAndTest() async {
        connectionMessage = nil
        didSucceed = false
        isTestingConnection = true
        defer { isTestingConnection = false }

        do {
            _ = try await environment.validateServerConnection(
                serverAddress: trimmedServerAddress,
                username: trimmedUsername,
                password: password,
                allowInsecureConnections: allowInsecure
            )

            var settings = environment.settingsStore.settings
            settings.serverURLString = trimmedServerAddress
            settings.username = trimmedUsername
            settings.allowInsecureConnections = allowInsecure
            environment.settingsStore.settings = settings
            environment.settingsStore.password = password
            await environment.settingsStore.persist()
            didSucceed = true
            WKInterfaceDevice.current().play(.success)
            onSuccess?()
        } catch {
            didSucceed = false
            connectionMessage = friendlyConnectionMessage(for: error)
        }
    }

    private func resetConnectionState() {
        guard !isTestingConnection else { return }
        didSucceed = false
        connectionMessage = nil
    }

    private func friendlyConnectionMessage(for error: Error) -> String {
        if let settingsError = error as? SettingsError {
            return settingsError.localizedDescription
        }

        if let clientError = error as? SubsonicClientError {
            switch clientError {
            case .server(let message):
                return message
            case .invalidResponse, .missingPayload, .unsupportedMediaType:
                return "Unable to connect to server."
            }
        }

        if error is URLError {
            return "Unable to connect to server."
        }

        return "Unable to connect to server."
    }
}
