import XCTest

@MainActor
final class InvoiceUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()
    }

    func testThreePrimaryDestinationsRemainReachableAfterRotation() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        XCTAssertEqual(tabBar.buttons.count, 3)

        let invoices = tabBar.buttons.matching(
            NSPredicate(format: "label == %@ OR label == %@", "請求書", "Invoices")
        ).firstMatch
        let settings = tabBar.buttons.matching(
            NSPredicate(format: "label == %@ OR label == %@", "設定", "Settings")
        ).firstMatch
        XCTAssertTrue(invoices.exists)
        XCTAssertTrue(settings.exists)

        invoices.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .portrait
    }

    func testLargeContentSizeKeepsInvoiceCreationReachable() throws {
        app.terminate()
        app.launchEnvironment["UIPreferredContentSizeCategoryName"] = "UICTContentSizeCategoryAccessibilityXXXL"
        app.launch()

        let createInvoice = app.buttons.matching(
            NSPredicate(format: "label == %@ OR label == %@", "請求書を作成", "Create invoice")
        ).firstMatch
        XCTAssertTrue(createInvoice.waitForExistence(timeout: 10))
        XCTAssertTrue(createInvoice.isHittable)
    }
}
