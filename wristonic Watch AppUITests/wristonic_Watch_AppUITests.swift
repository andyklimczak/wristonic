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

        app.buttons["Artists"].tap()
        XCTAssertTrue(app.staticTexts["Aurora Echo"].waitForExistence(timeout: 3))
        app.buttons["Aurora Echo"].tap()
        XCTAssertTrue(app.staticTexts["Analog Dawn"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSettingsDownloadsScreenShowsSeededAlbum() throws {
        let app = XCUIApplication()
        app.launchEnvironment["WRISTONIC_DEMO_MODE"] = "1"
        app.launchEnvironment["WRISTONIC_PRESEED_DOWNLOADS"] = "1"
        app.launch()

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Downloads"].waitForExistence(timeout: 3))
        app.buttons["Downloads"].tap()
        XCTAssertTrue(app.staticTexts["Analog Dawn"].waitForExistence(timeout: 3))
    }
}
