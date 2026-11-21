import XCTest
import Foundation
@testable import wristonic_Watch_App

func isRunningOnGitHubActions() -> Bool {
    let environment = ProcessInfo.processInfo.environment
    return environment["GITHUB_ACTIONS"] == "true" || environment["CI"] == "true"
}

func skipOnGitHubActions(_ reason: String) throws {
    if isRunningOnGitHubActions() {
        throw XCTSkip(reason)
    }
}

@MainActor
func waitForTestCondition(_ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(10)
    while !condition() && Date() < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
    _ = try XCTUnwrap(condition() ? true : nil, "Timed out waiting for condition")
}

@MainActor
final class TestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false
    private(set) var isWaiting = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            isWaiting = true
        }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
        isWaiting = false
    }
}

final class RecordingTransport: Transporting {
    private(set) var requests: [URLRequest] = []
    var dataResponses: [String: Data] = [:]
    var downloadData = testAudioData()
    var downloadMIMEType = "audio/wav"

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!
        return (dataResponses[endpoint(for: request)] ?? Data(), response)
    }

    func download(for request: URLRequest) async throws -> (URL, URLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": downloadMIMEType])!
        let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")
        try downloadData.write(to: temporaryURL)
        return (temporaryURL, response)
    }

    private func endpoint(for request: URLRequest) -> String {
        request.url?.lastPathComponent.replacingOccurrences(of: ".view", with: "") ?? ""
    }
}

final class ImmediateDownloadService: DownloadServing {
    private(set) var requests: [URLRequest] = []
    private(set) var allowedInsecureHosts: [String?] = []
    var downloadData = testAudioData()
    var mimeType = "audio/wav"
    var responsesByFormat: [String: (data: Data, mimeType: String)] = [:]
    private(set) var temporaryURLs: [URL] = []

    func download(
        for request: URLRequest,
        allowedInsecureHost: String?,
        onProgress: (@Sendable (Int64, Int64, Double) -> Void)?
    ) async throws -> DownloadedFile {
        requests.append(request)
        allowedInsecureHosts.append(allowedInsecureHost)
        let format = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "format" }?.value ?? "original"
        let payload = responsesByFormat[format] ?? (data: downloadData, mimeType: mimeType)
        let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".download")
        temporaryURLs.append(temporaryURL)
        try payload.data.write(to: temporaryURL)
        onProgress?(Int64(payload.data.count), Int64(payload.data.count), Double(payload.data.count))
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": payload.mimeType]
        )!
        return DownloadedFile(url: temporaryURL, response: response)
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

@MainActor
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
