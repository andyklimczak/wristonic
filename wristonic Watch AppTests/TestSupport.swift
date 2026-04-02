import Foundation
@testable import wristonic_Watch_App

final class RecordingTransport: Transporting {
    private(set) var requests: [URLRequest] = []
    var dataResponses: [String: Data] = [:]
    var downloadData = Data(repeating: 0x1, count: 2048)

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!
        return (dataResponses[endpoint(for: request)] ?? Data(), response)
    }

    func download(for request: URLRequest) async throws -> (URL, URLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!
        let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")
        try downloadData.write(to: temporaryURL)
        return (temporaryURL, response)
    }

    private func endpoint(for request: URLRequest) -> String {
        request.url?.lastPathComponent.replacingOccurrences(of: ".view", with: "") ?? ""
    }
}

@MainActor
func makeSettingsStore(name: String, capGB: Int = 8, offlineOnly: Bool = false) -> SettingsStore {
    let defaults = UserDefaults(suiteName: name) ?? .standard
    defaults.removePersistentDomain(forName: name)
    let settingsStore = SettingsStore(defaults: defaults, keychain: KeychainStore(service: name))
    settingsStore.settings.serverURLString = "https://demo.navidrome.local"
    settingsStore.settings.username = "demo"
    settingsStore.settings.storageCapGB = capGB
    settingsStore.settings.offlineOnly = offlineOnly
    settingsStore.password = "demo"
    return settingsStore
}

func makeClient(using transport: Transporting = DemoTransport()) throws -> SubsonicClient {
    SubsonicClient(
        configuration: ServerConfiguration(
            baseURL: URL(string: "https://demo.navidrome.local")!,
            username: "demo",
            password: "demo",
            preferredBitrateKbps: 192,
            allowInsecureConnections: false
        ),
        transport: transport
    )
}
