import XCTest
@testable import wristonic_Watch_App

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testValidatedServerURLAddsHTTPSWhenSchemeIsMissing() {
        let url = SettingsStore.validatedServerURL(from: "demo.navidrome.local", allowInsecureConnections: false)

        XCTAssertEqual(url?.absoluteString, "https://demo.navidrome.local")
    }

    func testValidatedServerURLRejectsMissingHost() {
        let url = SettingsStore.validatedServerURL(from: "https://", allowInsecureConnections: false)

        XCTAssertNil(url)
    }

    func testValidatedServerURLRejectsUnsupportedScheme() {
        let url = SettingsStore.validatedServerURL(from: "ftp://demo.navidrome.local", allowInsecureConnections: false)

        XCTAssertNil(url)
    }

    func testBuildServerConfigurationTrimsUsername() throws {
        let configuration = try SettingsStore.buildServerConfiguration(
            serverAddress: "demo.navidrome.local",
            username: "  demo  ",
            password: "secret",
            preferredBitrateKbps: 192,
            allowInsecureConnections: false
        )

        XCTAssertEqual(configuration.baseURL.absoluteString, "https://demo.navidrome.local")
        XCTAssertEqual(configuration.username, "demo")
    }

    func testBuildServerConfigurationRejectsMissingCredentials() {
        XCTAssertThrowsError(
            try SettingsStore.buildServerConfiguration(
                serverAddress: "demo.navidrome.local",
                username: " ",
                password: "",
                preferredBitrateKbps: 192,
                allowInsecureConnections: false
            )
        ) { error in
            XCTAssertEqual(error.localizedDescription, SettingsError.missingCredentials.localizedDescription)
        }
    }
}
