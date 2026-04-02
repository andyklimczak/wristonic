import Foundation

protocol Transporting {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
    func download(for request: URLRequest) async throws -> (URL, URLResponse)
}

final class URLSessionTransport: NSObject, Transporting, URLSessionDelegate {
    private lazy var session: URLSession = {
        URLSession(configuration: makeConfiguration())
    }()
    private let allowedHost: String?

    init(allowInsecureConnections: Bool, allowedHost: String?) {
        self.allowedHost = allowInsecureConnections ? allowedHost : nil
        super.init()
    }

    private lazy var insecureSession: URLSession = {
        URLSession(configuration: makeConfiguration(), delegate: self, delegateQueue: nil)
    }()

    private var activeSession: URLSession {
        allowedHost == nil ? session : insecureSession
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await activeSession.data(for: request)
    }

    func download(for request: URLRequest) async throws -> (URL, URLResponse) {
        try await activeSession.download(for: request)
    }

    private func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 600
        configuration.waitsForConnectivity = true
        configuration.urlCache = URLCache(memoryCapacity: 8_000_000, diskCapacity: 30_000_000)
        return configuration
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard
            let trust = challenge.protectionSpace.serverTrust,
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            challenge.protectionSpace.host == allowedHost
        else {
            return (.performDefaultHandling, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
    }
}
