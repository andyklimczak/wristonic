import XCTest
@testable import wristonic_Watch_App

@MainActor
final class ComplicationLaunchTests: XCTestCase {
    private let launchURL = URL(string: "wristonic://complication")!

    func testOpensLibraryWithoutLoadedAudio() {
        XCTAssertEqual(ComplicationLaunch.path(for: launchURL, hasTrack: false, hasStation: false), [])
    }

    func testOpensNowPlayingWithLoadedTrackOrStation() {
        XCTAssertEqual(ComplicationLaunch.path(for: launchURL, hasTrack: true, hasStation: false), [.nowPlaying])
        XCTAssertEqual(ComplicationLaunch.path(for: launchURL, hasTrack: false, hasStation: true), [.nowPlaying])
    }

    func testIgnoresUnrelatedURL() {
        let settingsURL = URL(string: "wristonic://settings")!
        XCTAssertNil(ComplicationLaunch.path(for: settingsURL, hasTrack: true, hasStation: false))
    }
}
