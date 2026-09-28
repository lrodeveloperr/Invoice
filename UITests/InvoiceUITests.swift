import XCTest

@MainActor
final class InvoiceUITests: XCTestCase {
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, japanese: String, english: String) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ OR label == %@", japanese, english)
        ).firstMatch
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
        let work = element(app, japanese: "作業", english: "Work")
        let invoices = element(app, japanese: "請求書", english: "Invoices")
        let settings = element(app, japanese: "設定", english: "Settings")
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
        let app = launchApp()
        app.terminate()
        app.launchEnvironment["UIPreferredContentSizeCategoryName"] = "UICTContentSizeCategoryAccessibilityXXXL"
        app.launch()

        let createInvoice = element(app, japanese: "請求書を作成", english: "Create invoice")
        XCTAssertTrue(createInvoice.waitForExistence(timeout: 10))
        XCTAssertTrue(createInvoice.isHittable)
        attachScreenshot("accessibility-xxxl")
    }
}
