import XCTest

@MainActor
final class InvoiceUITests: XCTestCase {
    private func launchApp(accessibilitySize: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        if accessibilitySize {
            app.launchEnvironment["UIPreferredContentSizeCategoryName"] = "UICTContentSizeCategoryAccessibilityXXXL"
        }
        app.launch()
        return app
    }

    private func identified(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testThreePrimaryDestinationsRemainReachableAfterRotation() throws {
        continueAfterFailure = false
        let app = launchApp()
        let work = identified(app, "tab.work")
        let invoices = identified(app, "tab.invoices")
        let settings = identified(app, "tab.settings")
        XCTAssertTrue(work.waitForExistence(timeout: 15))
        XCTAssertTrue(invoices.waitForExistence(timeout: 5))
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        attachScreenshot("primary-destinations-portrait")

        invoices.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        attachScreenshot("invoices-landscape")
        settings.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        attachScreenshot("settings-landscape")
        XCUIDevice.shared.orientation = .portrait
    }

    func testLargeContentSizeKeepsInvoiceCreationReachable() throws {
        continueAfterFailure = false
        let app = launchApp(accessibilitySize: true)

        let createInvoice = identified(app, "work.createInvoice")
        XCTAssertTrue(createInvoice.waitForExistence(timeout: 10))
        XCTAssertTrue(createInvoice.isHittable)
        attachScreenshot("accessibility-xxxl")
    }
}
