//
//  wristonic_Watch_AppUITests.swift
//  wristonic Watch AppUITests
//
//  Created by Andy Klimczak on 4/1/26.
//

import XCTest

final class wristonic_Watch_AppUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testBrowseArtistsAndAlbumsInDemoMode() throws {
        let app = XCUIApplication()
        app.launchEnvironment["WRISTONIC_DEMO_MODE"] = "1"
        app.launch()

        tapButton(startingWith: "Artists", in: app)
        let artistButton = button(startingWith: "Aurora Echo", in: app)
        XCTAssertTrue(artistButton.waitForExistence(timeout: 5))
        artistButton.tap()
        XCTAssertTrue(button(startingWith: "Analog Dawn", in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsDownloadsScreenShowsSeededAlbum() throws {
        let app = XCUIApplication()
        app.launchEnvironment["WRISTONIC_DEMO_MODE"] = "1"
        app.launchEnvironment["WRISTONIC_PRESEED_DOWNLOADS"] = "1"
        app.launch()

        tapButton(startingWith: "Settings", in: app)
        tapButton(startingWith: "Storage", in: app)
        tapButton(startingWith: "Downloads", in: app)
        XCTAssertTrue(app.staticTexts["Analog Dawn"].waitForExistence(timeout: 5))
    }

    private func button(startingWith labelPrefix: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", labelPrefix)).firstMatch
    }

    private func tapButton(startingWith labelPrefix: String, in app: XCUIApplication, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let target = button(startingWith: labelPrefix, in: app)
            if target.exists && target.isHittable {
                target.tap()
                return
            }
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("Button starting with \(labelPrefix) was not hittable")
    }
}
