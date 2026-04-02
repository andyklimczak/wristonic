//
//  wristonic_Watch_AppUITestsLaunchTests.swift
//  wristonic Watch AppUITests
//
//  Created by Andy Klimczak on 4/1/26.
//

import XCTest

final class wristonic_Watch_AppUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["WRISTONIC_DEMO_MODE"] = "1"
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
