import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings
    @Published var password: String
    @Published var savedBytes: Int64 = 0

    private let defaults: UserDefaults
    private let keychain: KeychainStore
    private let defaultsKey = "wristonic.settings"
    private let passwordFallbackKey = "wristonic.password.fallback"

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore(service: "com.andy.wristonic")) {
        self.defaults = defaults
        self.keychain = keychain

        if
            let data = defaults.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        {
            self.settings = decoded
        } else {
            self.settings = AppSettings()
        }

        self.password = (try? keychain.value(for: "password")) ?? defaults.string(forKey: passwordFallbackKey) ?? ""
        if let username = try? keychain.value(for: "username"), !username.isEmpty {
            self.settings.username = username
        }
    }

    var storagePolicy: StoragePolicy {
        StoragePolicy(capBytes: capBytes, savedBytes: savedBytes, pinnedBytes: 0)
    }

    var capBytes: Int64 {
        Int64(settings.storageCapGB) * 1_000_000_000
    }

    var canConnect: Bool {
        normalizedURL != nil && !settings.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    var hasSavedPassword: Bool {
        !password.isEmpty
    }

    var needsServerSetup: Bool {
        !canConnect
    }

    var normalizedURL: URL? {
        Self.validatedServerURL(from: settings.serverURLString, allowInsecureConnections: settings.allowInsecureConnections)
    }

    var normalizedServerAddress: String {
        Self.normalizedServerAddress(from: settings.serverURLString, allowInsecureConnections: settings.allowInsecureConnections)
    }

    func persist() async {
        if let encoded = try? JSONEncoder().encode(settings) {
            defaults.set(encoded, forKey: defaultsKey)
        }
        do {
            try keychain.set(settings.username, for: "username")
            if password.isEmpty {
                try keychain.removeValue(for: "password")
            } else {
                try keychain.set(password, for: "password")
            }
        } catch {
        }
        if password.isEmpty {
            defaults.removeObject(forKey: passwordFallbackKey)
        } else {
            defaults.set(password, forKey: passwordFallbackKey)
        }
    }

    func buildServerConfiguration() throws -> ServerConfiguration {
        try Self.buildServerConfiguration(
            serverAddress: settings.serverURLString,
            username: settings.username,
            password: password,
            preferredBitrateKbps: settings.preferredBitrateKbps,
            allowInsecureConnections: settings.allowInsecureConnections
        )
    }

    static func buildServerConfiguration(
        serverAddress: String,
        username: String,
        password: String,
        preferredBitrateKbps: Int,
        allowInsecureConnections: Bool
    ) throws -> ServerConfiguration {
        guard let url = validatedServerURL(from: serverAddress, allowInsecureConnections: allowInsecureConnections) else {
            throw SettingsError.invalidURL
        }

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !password.isEmpty else {
            throw SettingsError.missingCredentials
        }

        return ServerConfiguration(
            baseURL: url,
            username: trimmedUsername,
            password: password,
            preferredBitrateKbps: preferredBitrateKbps,
            allowInsecureConnections: allowInsecureConnections
        )
    }

    func updateSavedBytes(_ bytes: Int64) {
        savedBytes = bytes
    }

    func clearServerConfiguration() {
        settings.serverURLString = ""
        settings.username = ""
        settings.allowInsecureConnections = false
        password = ""
    }

    static func normalizedServerAddress(from serverAddress: String, allowInsecureConnections: Bool) -> String {
        let trimmed = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.contains("://") {
            return trimmed
        }
        let scheme = allowInsecureConnections ? "http://" : "https://"
        return scheme + trimmed
    }

    static func validatedServerURL(from serverAddress: String, allowInsecureConnections: Bool) -> URL? {
        let normalizedAddress = normalizedServerAddress(from: serverAddress, allowInsecureConnections: allowInsecureConnections)
        guard !normalizedAddress.isEmpty else {
            return nil
        }

        guard let components = URLComponents(string: normalizedAddress) else {
            return nil
        }

        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }

        guard let host = components.host, !host.isEmpty else {
            return nil
        }

        return components.url
    }
}

enum SettingsError: LocalizedError {
    case invalidURL
    case missingCredentials

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a valid server URL."
        case .missingCredentials:
            return "Enter a username and password."
        }
    }
}
