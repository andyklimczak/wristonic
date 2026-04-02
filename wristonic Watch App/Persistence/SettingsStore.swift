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
        URL(string: normalizedServerAddress)
    }

    var normalizedServerAddress: String {
        let trimmed = settings.serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.contains("://") {
            return trimmed
        }
        let scheme = settings.allowInsecureConnections ? "http://" : "https://"
        return scheme + trimmed
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
        guard let url = normalizedURL else {
            throw SettingsError.invalidURL
        }
        let username = settings.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, !password.isEmpty else {
            throw SettingsError.missingCredentials
        }
        return ServerConfiguration(
            baseURL: url,
            username: username,
            password: password,
            preferredBitrateKbps: settings.preferredBitrateKbps,
            allowInsecureConnections: settings.allowInsecureConnections
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
